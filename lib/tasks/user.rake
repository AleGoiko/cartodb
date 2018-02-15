namespace :user do
  namespace :deletion do
    desc 'Delete a user given a username'
    task :by_username, [:username] => [:environment] do |task, args|
      raise 'Please specify the username of the user to be deleted' if args[:username].blank?

      user = ::User.find(username: args[:username])
      raise "The username '#{args[:username]}' does not correspond to any user" if user.nil?

      raise 'Deletion aborted due to bad confirmation' if !deletion_confirmed?(user)

      user.destroy
    end

    desc 'Delete a user given an email'
    task :by_email, [:email] => [:environment] do |task, args|
      raise 'Please specify the email of the user to be deleted' if args[:email].blank?

      user = ::User.find(email: args[:email])
      raise "The email '#{args[:email]}' does not correspond to any user" if user.nil?

      raise 'Deletion aborted due to bad confirmation' if !deletion_confirmed?(user)

      user.destroy
    end

    def deletion_confirmed?(user)
      puts ""
      puts "You are about to delete the following user:"
      puts "\t> username: #{user.username}"
      puts "\t> email: #{user.email}"
      puts ""
      puts "Alongside '#{user.username}', the following will be deleted:"
      puts "\t> #{user.maps.length} maps"
      puts "\t> #{user.tables.count} datasets"
      puts ""
      puts "Type in the user's username (#{user.username}) to confirm:"

      confirm = STDIN.gets.strip

      confirm == user.username
    end
  end

  namespace :change do
    desc 'Change the number of maximum layers allowed on a map'
    task :max_layers, [:username, :max_layers] => [:environment] do |task, args|
      max_layers = args[:max_layers].to_i

      raise 'Please specify the username of the user to be modified' if args[:username].blank?
      raise 'Please specify a number of layers that is a positive integer' if max_layers < 1

      user = ::User.find(username: args[:username])
      raise "The username '#{args[:username]}' does not correspond to any user" if user.nil?

      old_max_layers = user.max_layers

      user.max_layers = max_layers
      user.save

      puts "Changed the number of max layers for '#{user.username}' from #{old_max_layers} to #{max_layers}."
    end
  end

  namespace :api_key do
    desc 'Creates default API Keys for user'
    task :create_default, [:emails_file] => [:environment] do |_, args|
      line = 0
      File.foreach(args[:emails_file]) do |email|
        email.strip!
        line += 1

        unless email =~ /.*@.*\..*/
          puts "Row #{line} is not an email: #{email}"
          next
        end

        user = User.first(email: email)

        if user.nil?
          puts "WARN: User #{email} not found"
        else
          begin
            user.create_api_keys
            puts "INFO: Api Keys created for #{user.email}"
          rescue => e
            puts "WARN: Unable to create api keys for user with email #{email}: #{e}"
          end
        end
      end
    end
  end
end
