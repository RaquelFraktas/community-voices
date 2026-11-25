Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "weeks#index"

  resources :reports, only: :create do
    get :compare, on: :collection
    resource :retry, only: :create, controller: "report_retries"
  end

  resource :embeddings, only: :show
  get "retrievals/stats", to: "retrieval_stats#show", as: :retrieval_stats
  resource :status, only: :show
end
