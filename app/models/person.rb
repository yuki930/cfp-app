class Person < ApplicationRecord
  has_many :invitations,  dependent: :destroy
  has_many :services,     dependent: :destroy
  has_many :participants, dependent: :destroy
  has_many :reviewer_participants, -> { where(role: ['reviewer', 'organizer']) }, class_name: 'Participant'
  has_many :reviewer_events, through: :reviewer_participants, source: :event
  has_many :organizer_participants, -> { where(role: 'organizer') }, class_name: 'Participant'
  has_many :organizer_events, through: :organizer_participants, source: :event
  has_many :speakers,     dependent: :destroy
  has_many :ratings,      dependent: :destroy
  has_many :comments,     dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :proposals, through: :speakers, source: :proposal
end
