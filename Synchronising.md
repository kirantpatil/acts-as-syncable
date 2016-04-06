I’ve recently been looking into how to synchronise two Rails applications together, one will be the master, the other the slave. When a record gets created/updated/deleted in one db, I want it to do similarly in the other. Why am I doing this? So I can have a Rails application on the client side with a local sqlite db, communicate with this via weborb from Flex/Apollo and then sync the database (perhaps the user is offline).

So, I’ve never read about synchronisation or implemented anything like this before, but I can see two main things crucial to synchronisation. Firstly, that the app can find the changes to it’s db since a last sync, and secondly that you can post create/update/delete information to the application and, if the lock version is correct (record hasn’t been updated since sync), perform the action.

So, again, two ways I can think of when trying to find changes in the db. Obviously destroy records won’t still be in the db, do it’s not as easy as searching for records updated at after the last sync time.

  1. Either we compare the db against a copy of the db, made at the last sync. Then we can compare the copy and find out updated/created/destroy records. This is the method that Joyent Slingshot uses.
> 2. Or we record changes incremental. When a record changes, it creates a ’sync’ record with the appropriate method, id and model name. This is easy to do with polymorphic associations.

I’ve developed two plugins (acts\_as\_synchronised) that do the methods above, the first saves the db in a yaml file (not in the db as it’s too large for my liking) and marks changes off that. The second has a sync model. Models marked as acts\_as\_syncable create sync records when they get CRUDed.

I think I prefer the latter method, as it requires much less processing (you don’t need compare every single record with a copy of the db), I’ll release the plugin as soon as I’ve tested it thoroughly.

Some issues I’ve thought off (and solved). Can you think of any more?

  1. Record A is created on Rails 1. Rails 1 syncs with Rails 2 and Rails 2 creates the record. However the record Id in Rails 2 is different from the record Id in Rails 1. Therefore we need a ‘real\_id’ column in the db. When one Rails app has synced up, it has a load of ids to real\_ids returned. Then it can just save the real\_id in the db.
> 2. Records need to be synced in order, with created first, and then updated and deleted next. Otherwise you’ll find that you’ll be editing/deleting records that don’t exists yet.
> 3. We need a GUID to associate sync times with. A user can have two machines, and be using them both. They both need to have different sync times which can’t be associated with a user\_id (since they’ve both got the same user\_id). Thus we need a GUID generated on installation. Then a ’sync\_time’ can be associated per installation, rather than per user.

I hope this has been interesting and I’m sure it’s an area that’ll need to be explored when the next generation of Rails apps come along, installed on the desktop.

