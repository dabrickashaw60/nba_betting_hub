# app/controllers/schedule_controller.rb
class ScheduleController < ApplicationController
  def update_schedule
    month = params[:month] # Get the selected month from the form

    # Call the scraper with the selected month
    Scrapers::ScheduleScraper.scrape_schedule(month)

    # Redirect to the root path with a notice that the schedule has been updated
    redirect_to root_path, notice: "Schedule updated for #{month.capitalize}."
  end
end
