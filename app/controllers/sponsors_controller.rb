class SponsorsController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :set_sponsor, only: %i[show]

  # GET /sponsors
  def index
    @sponsors = Sponsor.order(:name)
    @sponsors = @sponsors.where("lower(name) LIKE ?", "#{params[:letter].downcase}%") if params[:letter].present?
    @featured_sponsors = Sponsor.joins(:event_sponsors).group("sponsors.id").order("COUNT(event_sponsors.id) DESC").limit(25)
  end

  # GET /sponsors/1
  def show
    @back_path = sponsors_path
    @events_by_year = @sponsor.events.order(start_date: :desc).includes(:organisation).group_by { |event| event.start_date&.year || "Unknown" }
  end

  private

  def set_sponsor
    @sponsor = Sponsor.find_by(slug: params[:slug])

    redirect_to sponsors_path, status: :moved_permanently, notice: "Sponsor not found" if @sponsor.blank?
  end
end
