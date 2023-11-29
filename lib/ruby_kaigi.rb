module RubyKaigi
  # 2017
  KEYNOTES = %w(yukihiro_matz n0kada vnmakarov)
  KEYNOTE_SESSIONS = [125, 89, 126, 187, 197, 138]  # matz, justin, nalsh, nobu, matz, vnmakarov

  DISCUSSION_SESSIONS = [127, 172].freeze  # committers, committers
  LT_SESSIONS = [159].freeze  # LT

  module CfpApp
    def self.speakers(event)
      people = Speaker.joins(:proposal).includes(person: :services).merge(event.proposals.accepted.confirmed).each_with_object({}) do |sp, hash|
        person = sp.person
        tw = person.services.detect {|s| s.provider == 'twitter'}&.account_name
        gh = person.services.detect {|s| s.provider == 'github'}&.account_name
        id = tw || gh
        bio = if sp.bio.present? && (sp.bio != 'N/A')
          sp.bio
        else
          person.bio || ''
        end.gsub("\r\n", "\n").chomp
        h = {'id' => id, 'name' => person.name, 'bio' => bio, 'github_id' => gh, 'twitter_id' => tw, 'gravatar_hash' => Digest::MD5.hexdigest(person.email)}
        hash[id] = h
      end
      keynotes, speakers = people.partition {|p| KEYNOTES.include? p.first}

      speakers = {'keynotes' => keynotes.to_h, 'speakers' => speakers.sort_by {|p| p.first.downcase}.to_h}
      speakers.delete 'keynotes' if speakers['keynotes'].empty?
      speakers
    end

    def self.presentations(event)
      proposals = event.proposals.joins(:session).includes([{speakers: {person: :services}}, :session]).accepted.confirmed.order('sessions.conference_day, sessions.start_time, sessions.room_id')
      presentations = proposals.each_with_object({}) do |p, h|
        speakers = p.speakers.sort_by(&:id).map {|sp| sp.person.social_account }
        lang = p.custom_fields['spoken language in your talk'].downcase.in?(['ja', 'japanese', '日本語', 'Maybe Japanese (not sure until fix the contents)']) ? 'JA' : 'EN'
        type = p.session.id.in?(KEYNOTE_SESSIONS) ? 'keynote' : (p.session.id.in?(DISCUSSION_SESSIONS) ? 'discussion' : 'presentation')
        h[speakers.first] = {'title' => p.title, 'type' => type, 'language' => lang, 'description' => p.abstract.gsub("\r\n", "\n").chomp, 'speakers' => speakers.map {|sp| {'id' => sp}}}
      end
    end

    def self.schedule(event)
      first_date = event.start_date.to_date

      result = event.sessions.includes(proposal: {speakers: {person: :services}}).group_by(&:conference_day).sort_by {|day, _| day}.each_with_object({}) do |(day, sessions), schedule|
        events = sessions.group_by {|s| [s.start_time, s.end_time]}.sort_by {|(start_time, end_time), _| [start_time, end_time]}.map do |(start_time, end_time), sessions_per_time|
          event = {'type' => nil, 'begin' => start_time.strftime('%H:%M'), 'end' => end_time.strftime('%H:%M')}
          talks = sessions_per_time.sort_by(&:room_id).each_with_object({}) do |session, h|
            h[session.room.room_number] = session.proposal.speakers.first.person.social_account if session.proposal
          end
          if talks.any?
            event['type'] = sessions_per_time.any? {|s| s.id.in?(KEYNOTE_SESSIONS)} ? 'keynote' : 'talk'
            event['talks'] = talks
          elsif sessions_per_time.any? {|s| s.id.in?(LT_SESSIONS)}
            event['name'] = sessions_per_time.first.title
            event['type'] = 'lt'
          else
            event['name'] = sessions_per_time.first.title
            event['type'] = 'break'
          end
          event
        end
        schedule[(day - 1).days.since(first_date).strftime('%b%d').downcase] = {'events' => events}
      end
    end
  end

  class RKO
    def self.clone
      Dir.chdir '/tmp' do
        `git clone https://#{ENV['GITHUB_TOKEN']}@github.com/ruby-no-kai/rubykaigi2017.git`
        Dir.chdir 'rubykaigi2017' do
          `git checkout master`
          `git remote add rubykaigi-bot https://#{ENV['GITHUB_TOKEN']}@github.com/rubykaigi-bot/rubykaigi2017.git`
          `git pull --all`
        end
      end
      new '/tmp/rubykaigi2017'
    end

    def initialize(path)
      @path = path
    end

    %w(speakers sponsors schedule presentations).each do |name|
      define_method name do
        File.read "#{@path}/data/year_2017/#{name}.yml"
      end

      define_method "#{name}=" do |content|
        File.write "#{@path}/data/year_2017/#{name}.yml", content
      end

      define_method "pull_requested_#{name}" do
        begin
          `git checkout #{name}-from-cfpapp`
          File.read "#{@path}/data/year_2017/#{name}.yml"
        ensure
          `git checkout master`
        end
      end
    end

    def pr(title: 'From cfp-app', branch: "from-cfpapp-#{Time.now.strftime('%Y%m%d%H%M%S')}")
      Dir.chdir @path do
        `git checkout -b #{branch}`
        `git config user.name "RubyKaigi Bot" && git config user.email "amatsuda@rubykaigi.org"`
        `git commit -am '#{title}' && git push -u rubykaigi-bot HEAD`
        uri = URI 'https://api.github.com/repos/ruby-no-kai/rubykaigi2017/pulls'
        Net::HTTP.post uri, {'title' => title, 'head' => "rubykaigi-bot:#{branch}", 'base' => 'master'}.to_json, {'Authorization' => "token #{ENV['GITHUB_TOKEN']}"}
      end
    end
  end

  module Gist
    def self.sponsors_yml
      uri = URI 'https://api.github.com/gists/d6f1dd44017aac2ec4031aa9178f99e8'
      uri.query = URI.encode_www_form 'access_token': ENV['GIST_TOKEN']
      res = Net::HTTP.get(uri)
      JSON.parse(res)['files']['rubykaigi2017_sponsors.yml']['content']
    end
  end

  module Speakers
#       def self.get
#         uri = URI 'https://api.github.com/repos/ruby-no-kai/rubykaigi2017/contents/data/year_2017/speakers.yml'
#         uri.query = URI.encode_www_form access_token: #{ENV['GITHUB_TOKEN']}
#         res = Net::HTTP.get(uri)
#         Base64.decode64(JSON.parse(res))['content']
#       end
  end
end
