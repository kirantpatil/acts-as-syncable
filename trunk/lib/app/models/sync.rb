require 'open-uri'

class Sync < ActiveRecord::Base
 METHOD_CREATE = "create"
 METHOD_UPDATE = "update"
 METHOD_DESTROY = "destroy"
 
 belongs_to :method, :polymorphic => true
 
 cattr_accessor :stall_synching
 
 class << self
 	
 	
  def do(address, for_when, options = {}, url_header = {})
     sURI = URI.parse(address)
     
 	 http = Net::HTTP.new(sURI.host, sURI.port)
	 req = http.start do |http|
       request=Net::HTTP::Get.new(sURI.path + "/syncs/down.yaml",url_header)
       request.basic_auth(sURI.user, sURI.password) if sURI.user
       http.request(request) 
     end
     up(YAML.load(req.body)['syncs'])
     
     http = Net::HTTP.new(sURI.host, sURI.port)
     req = http.start do |http|
       request=Net::HTTP::Post.new(sURI.path + "/syncs/up.yaml",url_header) 
       request.content_type = 'application/x-yaml'
       request.body = down(for_when,options).to_yaml
       request.basic_auth(sURI.user, sURI.password) if sURI.user
       http.request(request)
     end
     res = YAML.load(req.body)[:syncs]
     res[:mapped_ids].each do |m|
      rec = Object.const_get(m[:class_name]).find(m[:id])
      rec.update_attributes(:real_id => m[:real_id]) if rec.respond_to?(:real_id)
     end
     res[:errors]
  end
  
  def add(crud, whatever)
   if Sync.stall_synching == :once
   	Sync.stall_synching = nil
    return
   elsif Sync.stall_synching == :all
    return
   end
   s = self.new
   s.crud = crud
   s.method = whatever
   if crud == METHOD_DESTROY and whatever.respond_to?(:real_id)
    s.deleted_id = whatever.real_id
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
    Object.const_get(s.method_type).exists?(s.method_id) ?
    	Hash.from_xml(Object.const_get(s.method_type).find(s.method_id).to_xml) : nil
   end
   updated.collect! do |s| 
   	Object.const_get(s.method_type).exists?(s.method_id) ?
    	Hash.from_xml(Object.const_get(s.method_type).find(s.method_id).to_xml) : nil
   end
   destroyed.collect!    {|s| {s.method_type => s.deleted_id} }
   #d.each {|dd| dd.destroy } # More than one sync per user
   {'syncs' => {'create' => created, 'update' => updated, 'destroy' => destroyed}}
  end
  
  def up(d, options = {})
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
     x.keys.each do |key|
      begin
      k = x[key]
      if !k['real_id']
       p = Object.const_get(key.camelize).find_by_real_id(k['id'])
      else
  	   p = Object.const_get(key.camelize).find(k['real_id'])
  	  end
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
       p = Object.const_get(key.camelize).find(k)
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
          
 end
 
end
