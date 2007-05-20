require 'open-uri'

class Sync < ActiveRecord::Base
 METHOD_CREATE = "create"
 METHOD_UPDATE = "update"
 METHOD_DESTROY = "destroy"
 
 belongs_to :method, :polymorphic => true
 
 cattr_accessor :stall_synching
 
 class << self
 	
 	
  def do(address, for_when, options = {}, url_header = {})
    do_up(address, for_when, options, url_header)
    do_down(address, for_when, options, url_header)
  end
  
  def do_up(address, for_when, options = {}, url_header = {})
    sURI = URI.parse(address) 
    http = Net::HTTP.new(sURI.host, sURI.port)
    req = http.start do |http|
     request=Net::HTTP::Get.new(sURI.path + "/syncs/down.yaml",url_header)
     request.basic_auth(sURI.user, sURI.password) if sURI.user
     http.request(request) 
    end
    up(YAML.load(req.body)['syncs'], for_when, options)  
  end
  
  def do_down(address, for_when, options = {}, url_header = {})
    sURI = URI.parse(address) 
    http = Net::HTTP.new(sURI.host, sURI.port)
    req = http.start do |http|
     request=Net::HTTP::Post.new(sURI.path + "/syncs/up.yaml",url_header) 
     request.content_type = 'application/x-yaml'
     request.body = down(for_when,options).to_yaml
     request.basic_auth(sURI.user, sURI.password) if sURI.user
     http.request(request)
    end
    res = YAML.load(req.body)[:syncs]
    Sync.disable_all
    res[:mapped_ids].each do |m|
     rec = Object.const_get(m[:class_name]).find(m[:id])
     rec.update_attributes(:real_id => m[:real_id]) if rec.respond_to?(:real_id)
    end
    Sync.enable_all
    res[:errors] # need to parse these
  end
  
  def add(crud, whatever)
   if Sync.stall_synching == :once
    Sync.enable_all
    return
   elsif Sync.stall_synching == :all
    return
   end
   s = self.new
   s.crud = crud
   s.method = whatever
   if crud == METHOD_DESTROY
    if whatever.respond_to?(:real_id)
     s.deleted_id = whatever.real_id
    else
     s.deleted_id = whatever.id
    end
   end
   if whatever.respond_to?(:created_by)
    s.for_id = whatever.created_by
   else
    s.for_id = whatever.id # user model
   end
   s.save
  end
 
  def down(for_when, options = {})
   d = with_scope(:find => { :conditions => ["updated_at > ?", for_when]}) do
    self.find(:all,options)
   end
     
   created   = d.select {|s| s.crud == METHOD_CREATE}
   updated   = d.select {|s| s.crud == METHOD_UPDATE}
   destroyed = d.select {|s| s.crud == METHOD_DESTROY}
   
   created.collect! do |s| 
    if Object.const_get(s.method_type).exists?(s.method_id)
     rc = Object.const_get(s.method_type).find(s.method_id)
     Hash.from_xml(rc.to_xml(rc.sync_options))
    end
   end
   updated.collect! do |s| 
    if Object.const_get(s.method_type).exists?(s.method_id)
     rc = Object.const_get(s.method_type).find(s.method_id)
     Hash.from_xml(rc.to_xml(rc.sync_options))
    end
   end
   destroyed.collect!    {|s| {s.method_type => s.deleted_id} }
   #d.each {|dd| dd.destroy } # More than one sync per user
   {'syncs' => {'create' => created, 'update' => updated, 'destroy' => destroyed, 'version' => version}}
  end
  
  def up(d, from_when, options = {})
   raise "Wrong version of syncing software, \
   your version is #{d['version']} and the \
   server is prepared for #{version}" if d['version'] and d['version'].first != version
  	
   Sync.disable_all
   errors = []
   mapped_ids = []
   with_scope(:find => options) do
    d['create'].each do |x|
     x.keys.each do |key|
      k = x[key]
      p = Object.const_get(key.camelize).new
      k.each do |nm,vl|
       begin
        p[nm] = vl unless nm == 'id'
       rescue
       end
      end
      (p.real_id = k['id']) if p.respond_to?(:real_id)
      p.save
      mapped_ids << {:class_name => p.class.name, :id => k['id'], :real_id => p.id}
      errors << p.errors
     end if x
    end if d['create']
    d['update'].each do |x|
     pu = pending_updates(for_when)
     x.keys.each do |key|
      begin
      k = x[key]
      if !k['real_id']
       p = Object.const_get(key.camelize).find_by_real_id(k['id'])
      else
       p = Object.const_get(key.camelize).find(k['real_id'])
      end
      compare_records(p, pu, errors)
      k.each do |nm,vl|
       begin
        p[nm] = vl unless nm == 'id'
       rescue => e
        puts e
       end
      end
      (p.real_id = k['id']) if p.respond_to?(:real_id)
      p.save
      errors << p.errors
      rescue ActiveRecord::RecordNotFound
       errors << "Record not created yet, need full sync"
      end
     end if x
    end if d['update']
    d['destroy'].each do |x|
      x.keys.each do |key|
       begin
       k = x[key]
       begin # is there a better way to do this?
        p = Object.const_get(key.camelize).find_by_real_id(k)
       rescue NoMethodError
        p = Object.const_get(key.camelize).find(k)
       end
       p.destroy
   	rescue ActiveRecord::RecordNotFound
  	 errors << "Record not created yet, need full sync"
 	end
       end if x
       end if d['destroy']
    end
    Sync.enable_all
    {:syncs => {:errors => errors, :mapped_ids => mapped_ids}}
  end
  
  def version
   '0.0.1'
  end

  def disable_once
   Sync.stall_synching = :once
  end
        
  def disable_all
   Sync.stall_synching = :all
  end
  
  def enable_all
   Sync.stall_synching = nil
   true
  end
  
  private
  
  def compare_records(current_record, pending_updates, errors)
   return if current_record.respond_to?(:real_id)
   ids = pending_updates.select {|i| i.method.id == current_record.id }
   ids.each do |i|
    errors << "Stale object error (#{i.id})"
    i.destroy
   end
    # furthur error checking needed
  end
  
  def pending_updates(for_when)
   self.find(:all, :conditions => ["updated_at > ? AND crud = ?", from_when, METHOD_UPDATE])
  end
          
 end
 
end
