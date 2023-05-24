# frozen_string_literal: true

environment
  <<~CODE
    config.generators do |g|
      g.template_engine :haml
      g.test_framework :rspec, fixture: false
      g.stylesheets     false
    end
  CODE

@project_name = ask("What is this project's name?")

def add_devise
  generate "devise:install"
  environment "config.action_mailer.default_url_options = { host: \"localhost\", port: 3000 }",
    env: "development"

  create_file "app/controllers/registrations_controller.rb" do
    <<~CODE
      class RegistrationsController < Devise::RegistrationsController
        before_action :one_user_registered?

        private

        def one_user_registered?
          if (User.count == 1) & user_signed_in?
            redirect_to root_path
          elsif User.count == 1
            redirect_to new_user_session_path
          end
        end
      end
    CODE
  end

  create_file "app/views/devise/sessions/new.html.haml" do
    <<~CODE
      %h2 Log in
      = render "devise/shared/links"
    CODE
  end

  create_file "app/views/devise/shared/_links.html.haml" do
    <<~CODE
      = link_to "Sign in with Gmail", user_google_oauth2_omniauth_authorize_path, class: "btn"
    CODE
  end
end

def scaffold_user
  generate :devise, "User", "avatar:string", "admin:boolean"

  # set default value for admin to false
  in_root do
    migration = Dir.glob("db/migrate/*").max_by { |f| File.mtime(f) }
    gsub_file migration, /:admin/, ":admin, default: false"
  end

  insert_into_file "app/controllers/application_controller.rb", before: "end" do
    "  protect_from_forgery with: :exception\n"
    "  before_action :authenticate_user!\n"
  end

  rails_command "db:migrate"
end

def add_google_omniauth
  in_root do
    gsub_file "app/models/user.rb", /:validatable/, ":validatable,"
  end

  insert_into_file "app/models/user.rb", before: "end" do
<<-CODE
         :omniauthable, :omniauth_providers => [:google_oauth2]

  def self.from_omniauth(auth)
    return false if User.count == 1

    data = auth.info

    if user = User.where(email: data["email"]).first
      user.update_attribute(:avatar, data["image"])
      return
    end

    User.create(
      email: data["email"],
      password: Devise.friendly_token[0,20],
      avatar: data["image"]
    )
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
      config.omniauth :google_oauth2,
        Rails.application.credentials.google_key,
        Rails.application.credentials.google_secret,
        {
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
end

def add_devise_routes
  in_root do
    gsub_file "config/routes.rb", /  devise_for(.*?)routing\.html\n/m,
<<-CODE
  root "pages#index"

  devise_for :users,
    skip: [:registrations],
    controllers: { omniauth_callbacks: "users/omniauth_callbacks" }

  as :user do
    get "users/sign_up" => "registrations#new", as: :new_user_registration
    post "users" => "registrations#create", as: :user_registration
    get "users/cancel" => "registrations#cancel", as: :cancel_user_registration
  end
CODE
  end
end

def scaffold_pages
  generate "scaffold", "Pages title:string description:text, user:references"
  rails "db:migrate"
end

def import_tailwind
  insert_into_file "app/assets/stylesheets/application.tailwind.css", before: "@tailwind base;" do
    <<~CODE
      @import url('https://fonts.googleapis.com/css2?family=Inter:wght@200;300;400;500;600&display=swap');

    CODE
  end
end

def add_layout
  remove_file "app/views/layouts/application.html.erb"

  create_file "app/views/layouts/application.html.haml" do
    <<~CODE
      !!!
      %html
        %head
          %title #{@project_name}
          %meta{name: "viewport", content: "width=device-width,initial-scale=1"}
          = csrf_meta_tags
          = csp_meta_tag
          = stylesheet_link_tag "tailwind", "inter-font", "data-turbo-track": "reload"
          = stylesheet_link_tag "application", "data-turbo-track": "reload"
          = javascript_importmap_tags

        %body
          = render "shared/navigation"
          = render "shared/messages"

          %main.container.mx-auto.mt-28.px-5.flex
            = yield
    CODE
  end

  create_file "app/views/shared/_messages.html.haml" do
  end

  create_file "app/views/shared/_navigation.html.haml" do
    <<~CODE
      nav
        .mx-auto max-w-7xl px-2 sm:px-6 lg:px-8
          = link_to #{@project_name}, root_path, class: "brand-logo"
          = link_to content_tag(:i, "menu", class: "text-white p-2 ml-2 cursor-pointer"), "#", data: { target: "mobile" }, class: "sidenav-trigger"

          %ulul.right
            - if current_user
              %li= link_to "Home", root_path
              %li= link_to "Logout", destroy_user_session_path, method: :delete
            - else
              %li= link_to "Login", new_user_session_path

          %ul.sidenav#mobile
            - if current_user
              %li= link_to "Home", root_path
              %li= link_to "Logout", destroy_user_session_path, method: :delete
            - else
              %li= link_to "Login", new_user_session_path
    CODE
  end
end

after_bundle do
  add_devise
  scaffold_user
  add_google_omniauth
  add_devise_routes
  scaffold_pages
  import_tailwind
  add_views
end
