require "fileutils"
require "shellwords"

# Copied from: https://github.com/mattbrictson/rails-template
# Add this template directory to source_paths so that Thor actions like
# copy_file and template resolve against our source files. If this file was
# invoked remotely via HTTP, that means the files are not present locally.
# In that case, use `git clone` to download them to a local temporary dir.
def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("jumpstart-"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      "--quiet",
      "https://github.com/scratchoo/jumpstart.git",
      tempdir
    ].map(&:shellescape).join(" ")

    if (branch = __FILE__[%r{jumpstart/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def rails_version
  @rails_version ||= Gem::Version.new(Rails::VERSION::STRING)
end

def rails_6?
  Gem::Requirement.new(">= 6.0.0.beta1", "< 7").satisfied_by? rails_version
end

def add_gems
  gem 'superuser', :git => 'git://github.com/scratchoo/superuser.git', :branch => 'pagy-pagination'
  gem 'bootstrap', '~> 4.3', '>= 4.3.1'
  #gem 'devise', '~> 4.6', '>= 4.6.1'
  gem 'devise', git: 'https://github.com/plataformatec/devise'
  gem 'devise-bootstrapped', github: 'excid3/devise-bootstrapped', branch: 'bootstrap4'
  gem 'devise_masquerade', '~> 0.6.2'
  gem 'name_of_person', '~> 1.1'
  gem 'sitemap_generator', '~> 6.0', '>= 6.0.1'

  gem 'recaptcha', '~> 5.0'
  gem 'friendly_id', '~> 5.2', '>= 5.2.5'
  gem 'mail_form', '~> 1.7', '>= 1.7.1'
  gem 'mailjet', '~> 1.5', '>= 1.5.4'
  gem 'httparty', '~> 0.17.0'
  gem 'aws-sdk-s3', '~> 1.40'
  gem 'delayed_job_active_record'
  gem 'daemons', '~> 1.3', '>= 1.3.1'
  gem 'delayed_job_web', '~> 1.4', '>= 1.4.3'
  gem 'pagy', '~> 3.3'
  gem 'whenever', '~> 1.0', require: false

  if rails_5?
    gsub_file "Gemfile", /gem 'sqlite3'/, "gem 'sqlite3', '~> 1.3.0'"
    gem 'webpacker', '~> 4.0.1'
  end
end

def set_application_name
  # Add Application Name to Config
  if rails_5?
    environment "config.application_name = Rails.application.class.parent_name"
  else
    environment "config.application_name = Rails.application.class.module_parent_name"
  end

  # Announce the user where he can change the application name in the future.
  puts "You can change application name inside: ./config/application.rb"
end

def add_users
  # Install Devise
  generate "devise:install"

  # Configure Devise
  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }",
              env: 'development'
  environment "config.action_mailer.default_url_options = { host: 'example.com' }",
              env: 'production'
  route "root to: 'home#index'"

  # Devise notices are installed via Bootstrap
  generate "devise:views:bootstrapped"

  # Create Devise User
  generate :devise, "User",
           "first_name",
           "last_name",
           "role",
           "announcements_last_read_at:datetime"

  # Set admin default to false
  # in_root do
  #   migration = Dir.glob("db/migrate/*").max_by{ |f| File.mtime(f) }
  #   gsub_file migration, /:admin/, ":admin, default: false"
  # end

  # Add Devise masqueradable to users
  # inject_into_file("app/models/user.rb", "omniauthable, :masqueradable, :", after: "devise :")
end


def add_javascript
  run "yarn add expose-loader jquery popper.js bootstrap data-confirm-modal local-time"

  content = <<-JS
const webpack = require('webpack')
environment.plugins.append('Provide', new webpack.ProvidePlugin({
  $: 'jquery',
  jQuery: 'jquery',
  Rails: '@rails/ujs'
}))
  JS

  insert_into_file 'config/webpack/environment.js', content + "\n", before: "module.exports = environment"
end

def copy_templates
  remove_file "app/assets/stylesheets/application.css"

  directory "app", force: true
  directory "config", force: true
  directory "lib", force: true

  route "get '/terms', to: 'home#terms'"
  route "get '/privacy', to: 'home#privacy'"
end


def add_announcements
  generate "model Announcement published_at:datetime announcement_type name description:text"
  route "resources :announcements, only: [:index]"
end

def add_notifications
  generate "model Notification recipient_id:bigint actor_id:bigint read_at:datetime action:string notifiable_id:bigint notifiable_type:string"
  route "resources :notifications, only: [:index]"
end

def add_multiple_authentication
    insert_into_file "config/routes.rb",
    ', controllers: { :sessions => "custom_sessions", registrations: "registrations" }',
    after: "  devise_for :users"
end

def add_whenever
  run "wheneverize ."
end

def add_friendly_id
  generate "friendly_id"

  insert_into_file(
    Dir["db/migrate/**/*friendly_id_slugs.rb"].first,
    "[5.2]",
    after: "ActiveRecord::Migration"
  )
end

def stop_spring
  run "spring stop"
end

def add_sitemap
  rails_command "sitemap:install"
end

# Main setup
add_template_repository_to_source_path

add_gems

after_bundle do
  set_application_name
  stop_spring
  add_users
  add_javascript
  add_announcements
  add_notifications
  add_multiple_authentication
  add_friendly_id

  copy_templates
  add_whenever
  add_sitemap

  # Migrate
  rails_command "db:create"
  rails_command "db:migrate"

  # Commit everything to git
  git :init
  git add: "."
  git commit: %Q{ -m 'Initial commit' }

  say
  say "Jumpstart app successfully created!", :blue
  say
  say "To get started with your new app:", :green
  say "cd #{app_name} - Switch to your new app's directory."

end
