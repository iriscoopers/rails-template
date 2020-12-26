# frozen_string_literal: true

gem "devise"
gem "slim-rails"
gem "omniauth-google-oauth2"
gem "httparty"

gem_group :development, :test do
  gem "rspec-rails"
  gem "dotenv-rails"
end

run "bundle install"

create_file ".env" do
  key = ask("What is your Google api's key?")
  secret = ask("What is your Google api's secret?")
  "GOOGLE_KEY=#{key}\nGOOGLE_SECRET=#{secret}"
end

environment "config.generators { |g| g.template_engine :slim }"

def setup_devise
  run "spring stop && spring start"
  generate "devise:install"
  environment "config.action_mailer.default_url_options = { host: \"localhost\", port: 3000 }",
    env: "development"
  generate :devise, "User", "avatar:string", "admin:boolean"

  # set default value for admin to false
  in_root do
    migration = Dir.glob("db/migrate/*").max_by { |f| File.mtime(f) }
    gsub_file migration, /:admin/, ":admin, default: false"
  end

  insert_into_file "app/controllers/application_controller.rb", before: "end" do
    "  before_action :authenticate_user!\n"
  end

  rails_command "db:migrate"
  create_file "app/views/devise/sessions/new.html.slim" do
    <<~CODE
      h2= "Log in"
      = render "devise/shared/links"
    CODE
  end

  create_file "app/views/devise/shared/_links.html.slim" do
    <<~CODE
      = link_to "Sign in with Gmail", user_google_oauth2_omniauth_authorize_path, class: "btn"
    CODE
  end
end

def setup_google_omniauth
  in_root do
    gsub_file "app/models/user.rb", /:validatable/, ":validatable,"
  end

  insert_into_file "app/models/user.rb", before: "end" do
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

  insert_into_file "config/initializers/devise.rb", before: "# ==> Warden configuration" do
    <<~CODE
      config.omniauth :google_oauth2, ENV["GOOGLE_KEY"], ENV["GOOGLE_SECRET"], {
        access_type: "offline",
        approval_prompt: "",
        prompt: "select_account",
        :image_aspect_ratio => "square",
        :image_size => 250
      }

    CODE
  end

  create_file "app/controllers/users/omniauth_callbacks_controller.rb" do
    <<~CODE
      class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
        def google_oauth2
          @user = User.from_omniauth(request.env["omniauth.auth"])

          if @user&.persisted?
            flash[:notice] = I18n.t "devise.omniauth_callbacks.success", :kind => "Google"
            sign_in_and_redirect @user, :event => :authentication
          else
            flash[:error] = "Sorry, you can't sign up with that email address"
            session["devise.google_data"] = request.env["omniauth.auth"].except(:extra)
            redirect_to root_path
          end
        end
      end
    CODE
  end

  in_root do
    gsub_file "config/routes.rb", /  devise_for(.*?)routing\.html\n/m,
<<-CODE
  devise_scope :user do
    root to: "devise/sessions#new"
  end

  devise_for :users,
    controllers: { omniauth_callbacks: "users/omniauth_callbacks" }
CODE
  end
end

def setup_materialize
  run "yarn add materialize-css jquery"

  insert_into_file "config/webpack/environment.js", after: "require('@rails/webpacker')\n" do
    <<~CODE
      const webpack = require('webpack')
      environment.plugins.append('Provide', new webpack.ProvidePlugin({
        $: 'jquery',
        jQuery: 'jquery',
        'window.jQuery': 'jquery'
      }))

    CODE
  end

  insert_into_file "app/javascript/packs/application.js", before: "require(\"@rails/ujs\")" do
    <<~CODE
      import "../stylesheets/application.sass";
      import "materialize-css/dist/js/materialize"
      import "jquery/dist/jquery"

    CODE
  end

  insert_into_file "app/javascript/packs/application.js", after: "require(\"channels\")\n" do
    <<~CODE
      $(document).on("turbolinks:load", function(e) {
        M.updateTextFields();
        $(".button-collapse").sidenav();
      });
    CODE
  end

  create_file "app/javascript/stylesheets/application.sass" do
    <<~CODE
      @import "materialize-css/dist/css/materialize"
      @import "variables"
      @import "base"
    CODE
  end

  create_file "app/javascript/stylesheets/variables.sass" do
    <<~CODE
      $primary-color: #2F4858 !default
      $secondary-color: #FFBB00 !default
    CODE
  end

  create_file "app/javascript/stylesheets/base.sass" do
<<-CODE
nav
  background-color: $primary-color
CODE
  end
end

def setup_views
  remove_file "app/views/layouts/application.html.erb"

  create_file "app/views/layouts/application.html.slim" do
    <<~CODE
      doctype html
      html
        head
          title= "Template"
          meta name="keywords" content="Template"
          meta name="author" content="author"
          meta charset="utf-8"
          meta name="viewport" content="width=device-width,initial-scale=1"

          = stylesheet_link_tag "https://fonts.googleapis.com/icon?family=Material+Icons"
          = stylesheet_link_tag "application", media: "all", "data-turbolinks-track": "reload"
          = javascript_pack_tag "application", "data-turbolinks-track": "reload"
          = csrf_meta_tags

        body
          = render "shared/navigation"
          = render "shared/messages"

          .container class="\#{controller_name} \#{action_name}"
            = yield
    CODE
  end

  create_file "app/views/shared/_messages.html.slim" do
  end

  create_file "app/views/shared/_navigation.html.slim" do
    <<~CODE
      nav
        .nav-wrapper
          = link_to "Template", root_path, class: "brand-logo"
          = link_to content_tag(:i, "menu", class: "material-icons"), "#", data: { target: "mobile" }, class: "sidenav-trigger"

          ul.right.hide-on-med-and-down
            - if current_user
              li= link_to "Home", root_path
              li= link_to "Logout", destroy_user_session_path, method: :delete
            - else
              li= link_to "Login", new_user_session_path

          ul.sidenav#mobile
            - if current_user
              li= link_to "Home", root_path
              li= link_to "Logout", destroy_user_session_path, method: :delete
            - else
              li= link_to "Login", new_user_session_path
    CODE
  end
end

after_bundle do
  setup_devise
  setup_google_omniauth
  setup_materialize
  setup_views
end
