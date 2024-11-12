Rails.application.routes.draw do
  root 'home#index' # This is your main landing page

  resources :teams, only: [:index, :show] do
    resources :players, only: [:show] do
      post 'update_stats', on: :member
    end
    post 'update_stats', on: :member
  end
  
  # Route to update schedule (handled by HomeController)
  post 'update_schedule', to: 'home#update_schedule'

  resources :players, only: [] do
    post 'update_stats', on: :member
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

  post 'scrape_previous_day_games', to: 'games#scrape_previous_day_games', as: 'scrape_previous_day_games'
  post 'scrape_date_range_games', to: 'games#scrape_date_range_games', as: 'scrape_date_range_games'


  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
