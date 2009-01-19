# == Schema Information
# Schema version: 20090118172133
#
# Table name: proposals
#
#  id                 :integer         not null, primary key
#  user_id            :integer         
#  presenter          :string(255)     
#  affiliation        :string(255)     
#  email              :string(255)     
#  website            :string(255)     
#  biography          :string(255)     
#  title              :string(255)     
#  description        :string(255)     
#  agreement          :boolean         default(TRUE)
#  created_at         :datetime        
#  updated_at         :datetime        
#  event_id           :integer         
#  submitted_at       :datetime        
#  note_to_organizers :text            
#  excerpt            :text(400)       
#  track_id           :integer         
#

class Proposal < ActiveRecord::Base
  # Mixins
  include SettingsCheckersMixin
  include CacheLookupsMixin
  cache_lookups_for :id, :order => 'submitted_at desc'

  # Associations
  belongs_to :event
  belongs_to :track
  has_many :comments
  has_and_belongs_to_many :users

  # Validations
  validates_presence_of :title, :description, :event_id
  validates_acceptance_of :agreement,                     :accept => true, :message => "must be accepted"
  validates_presence_of :excerpt,                         :if => :proposal_excerpts?
  validates_presence_of :presenter, :email, :biography,   :unless => :user_profiles?
  validate :validate_complete_user_profile,               :if => :user_profiles?

  # Protected attributes
  attr_protected :user_id, :event_id

  # Triggers
  before_save :populate_submitted_at

  # Return the first User owner. Burst into flames if no user or multiple users listed.
  def user
    raise ArgumentError, "Can't lookup user when in multiple presenters mode" if multiple_presenters?
    return self.users.first
  end

  # Does this +someone+ have privileges to alter this proposal?
  def can_alter?(someone)
    someone.admin? ? true : self.users.include?(someone)
  end

  # Normalize the URL.
  def website=(value)
    # TODO Should this throw an exception or invalidate object instead?
    begin
      website = URI.parse(value.strip)
      website.scheme = 'http' unless ['http','ftp'].include?(website.scheme) || website.scheme.nil?
      result = URI.parse(website.scheme.nil? ? 'http://'+value.strip : website.to_s).normalize.to_s
      write_attribute(:website, result)
    rescue URI::InvalidURIError => e
      write_attribute(:website, nil)
    end
  end

  # Return the comments as text.
  def comments_text
    return self.comments.inject("") do |string, comment|
      string +
        (string.empty? ? "" : "\n") +
        comment.email +
        ": " +
        comment.message
    end
  end

  # Save original created_at time because it doesn't survive database reloads.
  def populate_submitted_at
    self.submitted_at ||= self.created_at || Time.now
    return true
  end

  # Validation for making sure user has a complete profile
  def validate_complete_user_profile
    unless self.user_has_complete_profile?
      self.errors.add(:user, "must have a complete profile")
    end
  end

  # Does this profile have a user with a complete profile?
  def user_has_complete_profile?
    self.users.each do |user|
      return false if user.blank? || user.complete_profile? != true
    end
    return true
  end

  # Add user by record or id if needed. Return user object if added.
  def add_user(user)
    case user
    when Integer, String
      user = User.find(user)
    end

    if self.users.include?(user)
      return nil
    else
      self.users << user
      return user
    end
  end
end
