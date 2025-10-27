# == Route Map
#

Rails.application.routes.draw do
  namespace :sponsors do
    resources :missing, only: [:index]
  end

  resources :sponsors, param: :slug, only: [:index, :show] do
    resource :logos, only: [:show, :update], controller: "sponsors/logos"
  end

  extend Authenticator

  # static pages
  get "uses", to: "page#uses"
  get "/privacy", to: "page#privacy"
  get "/components", to: "page#components"
  get "/about", to: "page#about"
  get "/stickers", to: "page#stickers"
  get "/contributors", to: "page#contributors"
  get "/stamps", to: "stamps#index"

  # authentication
  get "/auth/failure", to: "sessions/omniauth#failure"
  get "/auth/:provider/callback", to: "sessions/omniauth#create"
  post "/auth/:provider/callback", to: "sessions/omniauth#create"
  resources :sessions, only: [:new, :create, :destroy]

  resource :password, only: [:edit, :update]
  namespace :identity do
    resource :email, only: [:edit, :update]
    resource :email_verification, only: [:show, :create]
    resource :password_reset, only: [:new, :edit, :create, :update]
  end

  authenticate :admin do
    mount MissionControl::Jobs::Engine, at: "/jobs"
    mount Avo::Engine, at: Avo.configuration.root_path
  end

  resources :topics, param: :slug, only: [:index, :show]
  resources :cfp, only: :index
  resources :countries, param: :country, only: [:index, :show]

  namespace :profiles do
    resources :connect, only: [:index, :show]
    resources :claims, only: [:create]
    resources :enhance, only: [:update], param: :slug
  end

  resources :contributions, only: [:index, :show], param: :step

  resources :templates, only: [:new, :create] do
    collection do
      get :new_child
      delete :delete_child
      get :speakers_search
      post :speakers_search_chips
    end
  end

  # resources
  namespace :analytics do
    resource :dashboards, only: [:show] do
      get :daily_page_views
      get :daily_visits
      get :monthly_page_views
      get :monthly_visits
      get :top_referrers
      get :top_landing_pages
      get :yearly_conferences
      get :yearly_talks
      get :top_searches
    end
  end

  resources :talks, param: :slug, only: [:index, :show, :update, :edit] do
    scope module: :talks do
      resources :recommendations, only: [:index]
      resource :watched_talk, only: [:create, :destroy, :update]
      resource :slides, only: :show
    end
  end

  resources :watched_talks, only: [:index, :destroy]

  resources :speakers, param: :slug, only: [:index, :show]
  resources :profiles, param: :slug, only: [:show, :update, :edit]
  resources :events, param: :slug, only: [:index, :show, :update, :edit] do
    resources :event_participations, only: [:create, :destroy]

    scope module: :events do
      collection do
        get "/past" => "past#index", :as => :past
        get "/archive" => "archive#index", :as => :archive
        get "/countries" => redirect("/countries")
        get "/countries/:country" => redirect { |params, _| "/countries/#{params[:country]}" }
        resources :cities, param: :city, only: [:index, :show]
      end

      resources :schedules, only: [:index], path: "/schedule" do
        get "/day/:date", action: :show, on: :collection, as: :day
      end
      resources :speakers, only: [:index]
      resources :participants, only: [:index]
      resources :involvements, only: [:index]
      resources :talks, only: [:index]
      resources :related_talks, only: [:index]
      resources :events, only: [:index]
      resources :videos, only: [:index]
      resources :sponsors, only: [:index]
      resources :cfp, only: [:index]
      resources :collectibles, only: [:index]
    end
  end
  resources :organisations, param: :slug, only: [:index, :show]

  namespace "spotlight" do
    resources :talks, only: [:index]
    resources :speakers, only: [:index]
    resources :events, only: [:index]
  end

  get "/featured" => "page#featured"

  resources :recommendations, only: [:index]

  get "leaderboard", to: "leaderboard#index"

  # admin
  namespace :admin, if: -> { Current.user & admin? } do
    resources :suggestions, only: %i[index update destroy]
  end

  get "/sitemap.xml", to: "sitemaps#show", defaults: {format: "xml"}

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", :as => :rails_health_check

  # Defines the root path route ("/")
  root "page#home"

  resources :watch_lists, only: [:index, :new, :create, :show, :edit, :update, :destroy], path: "bookmarks" do
    resources :talks, only: [:create, :destroy], controller: "watch_list_talks"
  end

  namespace :hotwire do
    namespace :native do
      namespace :v1 do
        get "home", to: "/page#home", defaults: {format: "json"}
        namespace :android do
          resource :path_configuration, only: :show
        end
        namespace :ios do
          resource :path_configuration, only: :show
        end
      end
    end
  end
end
