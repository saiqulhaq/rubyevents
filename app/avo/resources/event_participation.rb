class Avo::Resources::EventParticipation < Avo::BaseResource
  self.includes = [:user, :event]
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }
  self.search = {
    query: -> { query.joins(:user).where("users.name LIKE ?", "%#{params[:q]}%") }
  }

  def fields
    field :id, as: :id
    field :user_id, as: :number
    field :event_id, as: :number
    field :attended_as, as: :select, enum: ::EventParticipation.attended_as
    field :user, as: :belongs_to
    field :event, as: :belongs_to
  end

  def filters
    filter Avo::Filters::AttendedAs
  end
end
