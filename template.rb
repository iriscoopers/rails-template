# frozen_string_literal: true

gem "devise"
gem "slim"
gem "slim-rails"
gem "omniauth-google-oauth2"
gem "materialize-sass"
gem "httparty"
gem "jquery-rails"

gem_group :development, :test do
  gem "rspec-rails"
  gem "dotenv-rails"
end

run "bundle install"

create_file ".env" do
  key = ask("What is your Google api's key?")
  "GOOGLE_KEY=#{key}"
  secret = ask("What is your Google api's secret?")
  "GOOGLE_SECRET=#{secret}"
end

def setup_devise
  generate "devise:install"
  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }",
    env: "development"
  generate :devise, "User", "avatar:string", "admin:boolean"

  # set default value for admin to false
  in_root do
    migration = Dir.glob('db/migrate/*').max_by { |f| File.mtime(f) }
    gsub_file migration, /:admin/, ":admin, default: false"
  end

  insert_into_file "app/controllers/application_controller.rb", before: "end" do
    "before_action :authenticate_user!"
  end

  rails_command "be db:migrate"
  generate "devise:views -v sessions"
  create_file "app/views/devise/sessions/new.html.slim" do
    <<-CODE
    h2= "Log in"
    = render "devise/shared/links"
    CODE
  end
end

def setup_google_omniauth
  inject_into_file "app/models/user.rb", before: "end" do
    <<-CODE
               :omniauthable, :omniauth_providers => [:google_oauth2]

    def self.from_omniauth(auth)
      data = auth.info

      user = User.where(email: data["email"]).first

      if user
        user.update_attribute(:avatar, data["image"])
      else
        return false if User.count == 1

        user = User.create(
          email: data["email"],
          password: Devise.friendly_token[0,20],
          avatar: data["image"]
        )
      end

      user
    end

    def self.new_with_session(params, session)
      super.tap do |user|
        if data = session["devise.google_oauth2_data"] && session["devise.google_oauth2_data"]["extra"]["raw_info"]
          user.email = data["email"] if user.email.blank?
        end
      end
    end
    CODE
  end

  inject_into_file "config/initializers/devise.rb", before: "# ==> Warden configuration" do
    <<-CODE
      config.omniauth :google_oauth2, ENV['GOOGLE_KEY'], ENV['GOOGLE_SECRET'], {
        access_type: "offline",
        approval_prompt: "",
        prompt: "select_account",
        :image_aspect_ratio => "square",
        :image_size => 250
      }

    HEREDOC
  end
end
