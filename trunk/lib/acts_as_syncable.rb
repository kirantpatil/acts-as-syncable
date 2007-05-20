module ActiveRecord
  module Acts #:nodoc:
    module Syncable #:nodoc:
      
      def self.included(base)
        base.extend(ClassMethods)
      end
      
      module ClassMethods
         def acts_as_syncable(options = {})
            after_create :sync_create
            after_update :sync_update
            after_destroy :sync_destroy
	    has_many :syncs, :as => :method
            include ActiveRecord::Acts::Syncable::InstanceMethods        
          end
      end
      
      module InstanceMethods
    
        def sync_create
         Sync.add(Sync::METHOD_CREATE, self)                       
        end
        
        def sync_update
         Sync.add(Sync::METHOD_UPDATE, self)
        end
        
        def sync_destroy
         Sync.add(Sync::METHOD_DESTROY, self)     
        end
        
        def sync_options
         {}
        end
        
      end # InstanceMethods
    end # Syncable
  end # Acts
end # ActiveRecord