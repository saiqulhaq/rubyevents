class ProfilesController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :set_user, only: %i[show edit update]
  before_action :set_user_favorites, only: %i[show]
  before_action :set_mutual_events, only: %i[show]
  include Pagy::Backend
  include RemoteModal
  include WatchedTalks

  respond_with_remote_modal only: [:edit]

  # GET /profiles/:slug
  def show
    load_profile_data_for_show
    set_meta_tags(@user)
  end

  # GET /profiles/:slug/edit
  def edit
    set_modal_options(size: :lg)
  end

  # PATCH/PUT /profiles/:slug
  def update
    suggestion = @user.create_suggestion_from(params: user_params, user: Current.user)
    if suggestion.persisted?
      redirect_to profile_path(@user), notice: suggestion.notice
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def load_profile_data_for_show
    @talks = @user.kept_talks.includes(:speakers, event: :organisation, child_talks: :speakers).order(date: :desc)
    @talks_by_kind = @talks.group_by(&:kind)
    @topics = @user.topics.approved.tally.sort_by(&:last).reverse.map(&:first)
    # Load participated events (from event_participations)
    @events = @user.participated_events.includes(:organisation).distinct.in_order_of(:attended_as, EventParticipation.attended_as.keys)
    @events_with_stickers = @events.select(&:sticker?)

    event_participations = @user.event_participations.includes(:event).where(event: @events)
    @participations = event_participations.index_by(&:event_id)

    @events_by_year = @events.group_by { |event| event.start_date&.year || "Unknown" }

    # Group events by country for the map tab
    @countries_with_events = @events.group_by(&:country_code)
      .map { |code, events| [ISO3166::Country.new(code), events] }
      .reject { |country, _| country.nil? }
      .sort_by { |country, _| country.translations["en"] }

    @involved_events = @user.involved_events.includes(:organisation).distinct.order(start_date: :desc)
    event_involvements = @user.event_involvements.includes(:event).where(event: @involved_events)
    involvement_lookup = event_involvements.group_by(&:event_id)

    @involvements_by_role = {}
    @involved_events.each do |event|
      involvements = involvement_lookup[event.id] || []
      involvements.each do |involvement|
        @involvements_by_role[involvement.role] ||= []
        @involvements_by_role[involvement.role] << event
      end
    end

    @stamps = Stamp.for_user(@user)

    @back_path = speakers_path
  end

  helper_method :user_kind
  def user_kind
    return params[:user_kind] if params[:user_kind].present? && Rails.env.development?
    return :admin if Current.user&.admin?
    return :owner if @user.managed_by?(Current.user)
    return :signed_in if Current.user.present?

    :anonymous
  end

  def set_user
    @user = User.includes(:talks, :passports).find_by(slug: params[:slug])

    # TODO review this redirection as it causes some issues with the redirect loop
    # # When the user is found from its slug, but the github handle is different, we need to redirect to the github handle
    # if @user.present? && @user.github_handle.present? && @user.github_handle != params[:slug]
    #   return redirect_to profile_path(@user.github_handle), status: :moved_permanently
    # end

    @user = User.includes(:talks).find_by_github_handle(params[:slug]) unless @user.present?

    redirect_to speakers_path, status: :moved_permanently, notice: "User not found" if @user.blank?
    redirect_to profile_path(@user.canonical) if @user&.canonical.present?
  end

  def user_params
    params.require(:user).permit(
      :name,
      :github_handle,
      :twitter,
      :bsky,
      :linkedin,
      :mastodon,
      :bio,
      :website,
      :location,
      :speakerdeck,
      :pronouns_type,
      :pronouns,
      :slug
    )
  end

  def set_mutual_events
    @mutual_events = if Current.user
      @user.participated_events.where(id: Current.user.participated_events).distinct.order(start_date: :desc)
    else
      Event.none
    end
  end

  def set_user_favorites
    return unless Current.user

    @user_favorite_talks_ids = Current.user.default_watch_list.talks.ids
  end
end
