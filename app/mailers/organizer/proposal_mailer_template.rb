class Organizer::ProposalMailerTemplate
  include Rails.application.routes.url_helpers

  def initialize(template, event, proposal, tag_whitelist = [])
    @template = template
    @event = event
    @proposal = proposal
    @tags = build_tags(tag_whitelist)
  end

  def render
    replace_link_tags
    replace_simple_tags
    @template.html_safe
  end

  private

  attr_reader :tags


  # ::link text|tag_for_url::
  def replace_link_tags
    @template = @template.gsub(/::([^:]+?)\|([^:]+?)::/) do
      "[#{$1}](#{substitute_tag($2)})"
    end
  end

  # ::tag_for_replacement::
  def replace_simple_tags
    @template = @template.gsub(/::([^:]+?)::/) do
      substitute_tag($1)
    end
  end

  def substitute_tag(tag)
    tags[tag] || tag
  end

  def confirmation_link
    confirm_proposal_url(url_params(slug: @event.slug, uuid: @proposal))
  end

  def url_params(hash)
    hash.merge(ActionMailer::Base.default_url_options)
  end

  def build_tags(tag_whitelist)
    whitelist = tag_whitelist.map(&:to_s)

    tags = {
      'proposal_title' => @proposal.title,
      'confirmation_link' => confirmation_link
    }

    tags.select! { |k| whitelist.include?(k) } if whitelist.any?

    tags
  end
end
