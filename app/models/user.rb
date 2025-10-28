# rubocop:disable Layout/LineLength
# == Schema Information
#
# Table name: users
#
#  id                  :integer          not null, primary key
#  admin               :boolean          default(FALSE), not null
#  bio                 :text             default(""), not null
#  bsky                :string           default(""), not null
#  bsky_metadata       :json             not null
#  email               :string           indexed
#  github_handle       :string
#  github_metadata     :json             not null
#  linkedin            :string           default(""), not null
#  location            :string           default("")
#  mastodon            :string           default(""), not null
#  name                :string           indexed
#  password_digest     :string
#  pronouns            :string           default(""), not null
#  pronouns_type       :string           default("not_specified"), not null
#  slug                :string           default(""), not null, uniquely indexed
#  speakerdeck         :string           default(""), not null
#  talks_count         :integer          default(0), not null
#  twitter             :string           default(""), not null
#  verified            :boolean          default(FALSE), not null
#  watched_talks_count :integer          default(0), not null
#  website             :string           default(""), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  canonical_id        :integer          indexed
#
# Indexes
#
#  index_users_on_canonical_id         (canonical_id)
#  index_users_on_email                (email)
#  index_users_on_lower_github_handle  (lower(github_handle)) UNIQUE WHERE github_handle IS NOT NULL AND github_handle != ''
#  index_users_on_name                 (name)
#  index_users_on_slug                 (slug) UNIQUE WHERE slug IS NOT NULL AND slug != ''
#
# rubocop:enable Layout/LineLength
class User < ApplicationRecord
  include ActionView::RecordIdentifier
  include Sluggable
  include Suggestable
  include User::Searchable

  configure_slug(attribute: :name, auto_suffix_on_collision: true)

  GITHUB_URL_PATTERN = %r{\A(https?://)?(www\.)?github\.com/}i

  PRONOUNS = {
    "Not specified": :not_specified,
    "Don't specify": :dont_specify,
    "they/them": :they_them,
    "she/her": :she_her,
    "he/him": :he_him,
    Custom: :custom
  }.freeze

  has_secure_password validations: false

  # Authentication and user-specific associations
  has_many :sessions, dependent: :destroy, inverse_of: :user
  has_many :connected_accounts, dependent: :destroy
  has_many :passports, -> { passport }, class_name: "ConnectedAccount"
  has_many :watch_lists, dependent: :destroy
  has_many :watched_talks, dependent: :destroy

  # Speaker functionality associations
  has_many :user_talks, dependent: :destroy, inverse_of: :user
  has_many :talks, through: :user_talks, inverse_of: :speakers
  has_many :kept_talks, -> { joins(:user_talks).where(user_talks: {discarded_at: nil}).distinct },
    through: :user_talks, inverse_of: :speakers, class_name: "Talk", source: :talk
  has_many :events, -> { distinct }, through: :talks, inverse_of: :speakers
  has_many :aliases, class_name: "User", foreign_key: "canonical_id"
  has_many :topics, through: :talks

  # Event participation associations
  has_many :event_participations, dependent: :destroy
  has_many :participated_events, through: :event_participations, source: :event
  has_many :speaker_events, -> { where(event_participations: {attended_as: :speaker}) },
    through: :event_participations, source: :event
  has_many :keynote_speaker_events, -> { where(event_participations: {attended_as: :keynote_speaker}) },
    through: :event_participations, source: :event
  has_many :visitor_events, -> { where(event_participations: {attended_as: :visitor}) },
    through: :event_participations, source: :event

  has_many :event_involvements, as: :involvementable, dependent: :destroy
  has_many :involved_events, through: :event_involvements, source: :event

  belongs_to :canonical, class_name: "User", optional: true
  has_one :contributor, dependent: :nullify

  has_object :profiles
  has_object :location_info
  has_object :talk_recommender
  has_object :watched_talk_seeder
  has_object :speakerdeck_feed

  validates :email, format: {with: URI::MailTo::EMAIL_REGEXP}, allow_blank: true
  validates :github_handle, presence: true, uniqueness: true, allow_blank: true
  validates :canonical, exclusion: {in: ->(user) { [user] }, message: "can't be itself"}

  normalizes :github_handle, with: ->(value) { normalize_github_handle(value) }

  # Speaker-specific normalizations
  normalizes :twitter, with: ->(value) { value.gsub(%r{https?://(?:www\.)?(?:x\.com|twitter\.com)/}, "").gsub(/@/, "") }
  normalizes :bsky, with: ->(value) {
    value.gsub(%r{https?://(?:www\.)?(?:x\.com|bsky\.app/profile)/}, "").gsub(/@/, "")
  }
  normalizes :linkedin, with: ->(value) { value.gsub(%r{https?://(?:www\.)?(?:linkedin\.com/in)/}, "") }

  normalizes :mastodon, with: ->(value) {
    return value if value&.match?(URI::DEFAULT_PARSER.make_regexp)
    return "" unless value.count("@") == 2

    _, handle, instance = value.split("@")

    "https://#{instance}/@#{handle}"
  }

  normalizes :website, with: ->(website) {
    return "" if website.blank?

    # if it already starts with https://, return as is
    return website if website.start_with?("https://")

    # if it starts with http://, return as is
    return website if website.start_with?("http://")

    # otherwise, prepend https://
    "https://#{website}"
  }

  encrypts :email, deterministic: true

  before_validation if: -> { email.present? } do
    self.email = email&.downcase&.strip
  end

  before_validation if: :email_changed?, on: :update do
    self.verified = false
  end

  # Seed watched talks for new users in development
  after_create :seed_development_watched_talks, if: -> { Rails.env.development? }

  # Speaker scopes
  scope :with_talks, -> { where.not(talks_count: 0) }
  scope :speakers, -> { where("talks_count > 0") }
  scope :with_github, -> { where.not(github_handle: [nil, ""]) }
  scope :without_github, -> { where(github_handle: [nil, ""]) }
  scope :canonical, -> { where(canonical_id: nil) }
  scope :not_canonical, -> { where.not(canonical_id: nil) }

  def self.normalize_github_handle(value)
    value
      .gsub(GITHUB_URL_PATTERN, "")
      .delete("@")
      .strip
  end

  def self.reset_talks_counts
    find_each do |user|
      user.update_column(:talks_count, user.talks.count)
    end
  end

  def self.find_by_github_handle(handle)
    return nil if handle.blank?
    where("lower(github_handle) = ?", handle.downcase).first
  end

  # User-specific methods
  def default_watch_list
    @default_watch_list ||= watch_lists.first || watch_lists.create(name: "Bookmarks")
  end

  def main_participation_to(event)
    event_participations.in_order_of(:attended_as, EventParticipation.attended_as.keys).where(event: event).first
  end

  # Speaker-specific methods (adapted from Speaker model)
  def title
    name
  end

  def canonical_slug
    canonical&.slug
  end

  def verified?
    connected_accounts.find { |account| account.provider == "github" }
  end

  def contributor?
    contributor.present?
  end

  def managed_by?(visiting_user)
    return false unless visiting_user.present?
    return true if visiting_user.admin?

    self == visiting_user
  end

  def avatar_url(...)
    bsky_avatar_url(...) || github_avatar_url(...) || fallback_avatar_url(...)
  end

  def avatar_rank
    return 1 if bsky_avatar_url.present?
    return 2 if github_avatar_url.present?

    3
  end

  def custom_avatar?
    bsky_avatar_url.present? || github_avatar_url.present?
  end

  def bsky_avatar_url(...)
    bsky_metadata.dig("avatar")
  end

  def github_avatar_url(size: 200)
    return nil if github_handle.blank?

    metadata_avatar_url = github_metadata.dig("profile", "avatar_url")

    return "#{metadata_avatar_url}&size=#{size}" if metadata_avatar_url.present?

    "https://github.com/#{github_handle}.png?size=#{size}"
  end

  def fallback_avatar_url(size: 200)
    url_safe_initials = name.split(" ").map(&:first).join("+")

    "https://ui-avatars.com/api/?name=#{url_safe_initials}&size=#{size}&background=DC133C&color=fff"
  end

  def broadcast_header
    broadcast_update target: dom_id(self, :header_content), partial: "profiles/header_content", locals: {user: self}
  end

  def to_meta_tags
    {
      title: name,
      description: meta_description,
      og: {
        title: name,
        type: :website,
        image: {
          _: github_avatar_url,
          alt: name
        },
        description: meta_description,
        site_name: "RubyEvents.org"
      },
      twitter: {
        card: "summary",
        site: "@#{twitter}",
        title: name,
        description: meta_description,
        image: {
          src: github_avatar_url
        }
      }
    }
  end

  def to_combobox_display
    name
  end

  def meta_description
    <<~HEREDOC
      Discover all the talks given by #{name} on subjects related to Ruby language or Ruby Frameworks such as Rails, Hanami and others
    HEREDOC
  end

  def assign_canonical_speaker!(canonical_speaker:)
    return if canonical_speaker.blank?

    ActiveRecord::Base.transaction do
      self.canonical = canonical_speaker
      self.github_handle = nil
      save!

      user_talks.each do |user_talk|
        UserTalk.create(talk: user_talk.talk, user: canonical_speaker)
      end

      # We need to destroy the remaining user_talks. They can be remaining given the unicity constraint
      # on the user_talks table. The update above swallows the error if the user_talk duet exists already
      UserTalk.where(user_id: id).destroy_all
    end
  end

  def primary_speaker
    canonical || self
  end

  def suggestion_summary
    <<~HEREDOC
      Speaker: #{name}
      github_handle: #{github_handle}
      twitter: #{twitter}
      website: #{website}
      bio: #{bio}
    HEREDOC
  end

  def to_mobile_json(request)
    {
      id: id,
      name: name,
      slug: slug,
      avatar_url: avatar_url,
      url: Router.profile_url(self, host: "#{request.protocol}#{request.host}:#{request.port}")
    }
  end

  def assign_canonical_user!(canonical_user:)
    ActiveRecord::Base.transaction do
      self.canonical = canonical_user
      self.github_handle = nil
      save!

      user_talks.each do |user_talk|
        UserTalk.create(talk: user_talk.talk, user: canonical_user)
      end

      # We need to destroy the remaining user_talks. They can be remaining given the unicity constraint
      # on the user_talks table. The update above swallows the error if the user_talk duet exists already
      UserTalk.where(user_id: id).destroy_all
    end
  end

  def set_slug
    self.slug = slug.presence || github_handle.presence&.downcase
    super
  end

  def speakerdeck_user_from_slides_url
    handles = talks
      .map(&:static_metadata).compact
      .map(&:slides_url).compact
      .select { |url| url.include?("speakerdeck.com") }
      .map { |url| url.split("/")[3] }.uniq

    (handles.count == 1) ? handles.first : nil
  end

  def to_param
    return github_handle if github_handle.present?

    slug
  end

  private

  def seed_development_watched_talks
    watched_talk_seeder.seed_development_data
  end
end
