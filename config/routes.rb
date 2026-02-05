Rails.application.routes.draw do
  get 'depth_charts/index'
  get 'depth_charts/show'
  root 'home#index' # This is your main landing page

  resources :teams, only: [:index, :show] do
    member do
      post 'update_stats' # for individual team stats update
    end
  
    resources :players, only: [:show] do
      member do
        post 'update_stats' # for individual player stats update
        get 'filter_games' # for filtering the last 5 games based on a teammate
      end
    end
  
    collection do
      get 'defense_vs_position' # view for all teams' defense vs position
    end
  end  

  post 'update_schedule', to: 'home#update_schedule'

  post 'update_injuries', to: 'home#update_injuries'

  resources :projections, only: [:index] do
    collection do
      post :generate
      get  :results
    end
  end

  resources :players, only: [] do
    post 'update_stats', on: :member
    collection do
      get 'live_search', to: 'players#live_search'
    end
  end

  resources :games, only: [:show] do
    member do
      post 'scrape_box_score' # This is a member route, acting on a specific game
    end
    collection do
      post 'scrape_date_range_games' # This is a collection route, acting on the entire resource
    end
  end
  

  # Standings routes
  get 'standings', to: 'standings#index', as: 'standings'
  post 'standings/update', to: 'standings#update', as: 'update_standings'

  post 'scrape_previous_day_games', to: 'home#scrape_previous_day_games', as: 'scrape_previous_day_games'


  post 'scrape_date_range_games', to: 'games#scrape_date_range_games', as: 'scrape_date_range_games'


  # Health check
  get "up" => "rails/health#show", as: :rails_health_check


  ### TEMP DEBUG ###
  get "debug/team_stats/:team_id", to: "debug#team_stats"

  resources :depth_charts, only: [:index, :show]


end
