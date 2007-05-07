require 'acts_as_syncable'
require 'app/models/sync'

ActiveRecord::Base.send(:include, ActiveRecord::Acts::Syncable)