namespace :v1_to_v2 do
  desc ""
  task fill_schema_migration: :environment do
    con = ActiveRecord::Base.connection
    con.execute("insert into schema_migrations(version) values ('20160614162404')")
    con.execute("insert into schema_migrations(version) values ('20160713174249')")
    con.execute("insert into schema_migrations(version) values ('20160804194731')")
    con.execute("insert into schema_migrations(version) values ('20160923182207')")
    con.execute("insert into schema_migrations(version) values ('20160927205019')")
    con.execute("insert into schema_migrations(version) values ('20180106144145')")
    con.execute("insert into schema_migrations(version) values ('20180111175100')")
  end

  desc ""
  task apply: :environment do
    Teammate.delete_all
    User.delete_all
    ActiveRecord::Base.transaction do
      Person.find_each do |person|
        # v1では person has_many services でしたが、 v2 では user has_one service という関連になっています
        # v1のときに、ログイン済みの状態で別のProviderを経由してログインをすると新たにServiceのレコードが作成されます
        # https://github.com/ruby-no-kai/cfp-app/blob/rubykaigi2019/app/models/person.rb#L63-L66
        # ここでは2つ service が存在したら決め打ちで github でアカウントの移行を試みています。
        if person.services.count == 2
          service = person.services.find_by(provider: "github")
        else
          service = person.services.first
        end

        # Personだけ存在してServiceがない場合があります。
        # その場合はログインができないアカウントになるので、今回の移行処理では無視します
        # 一応、該当するpersonが1件もproposalを持っていないことも確認しています
        if service.nil?
          if person.proposals.count >= 1
            p person
            p "#{person.id} has proposals!"
          end

          service = Service.new(
            provider: "UNKNOWN",
            uid: "9999999999",
            uemail: "unknown-account-#{person.id}@example.com"
          )
        end

        # 今まではOAuthによるログインしか提供していなかったので
        # 下記の実装を参考にダミーでパスワードを生成してそれを保存します。
        # https://github.com/ruby-no-kai/cfp-app/blob/d5973b46ea436e83d04a826a4b1fd44c119b1f8a/app/models/user.rb#L41
        password = Devise.friendly_token[0,20]

        # `@` を別の記号にしている方がいるため email のフォーマットにそぐわなく、Validationエラーになる
        # 認証に使えないので Devise が提供する正規表現にマッチしない場合は、空文字を保存するようにします
        # 今まではOAuthでしか認証する仕組みがなかったので、特定の誰かがログインできなくなる、ということは起きません
        email = person.email || service.uemail || ""
        unless Devise.email_regexp.match? email
          email = ""
        end

        # 172と252 はメールアドレスが重複しているのでログインできない方のメールアドレスを書き換えます。
        if person.id == 172
          email = "duplicated-account-#{person.id}@example.com"
        end

        # 以前のRubyKaigiのタイムテーブルを生成する都合上重複したアカウントが存在します
        # v2 では email が被り一意制約エラーが発生するのでダミーのメールアドレスを挿入します
        # Person.where(email: EMAIL).pluck(:id) => [61, 588]
        if person.id == 588
          email = "dummy-account-#{person.id}@example.com"
        end

        user = User.new(
          id: person.id,
          name: person.name || service.account_name,
          email: email,
          password: password,
          password_confirmation: password,
          bio: person.bio,
          admin: person.admin,
          provider: service.provider,
          uid: service.uid
        )
        # これをしないと devise.gem がメールを送ってしまう。
        # PersonからUserへの移行なのでv1の時代からログインが出来ていたアカウントは確認済みにする。
        user.skip_confirmation_notification!
        user.skip_confirmation!
        user.save!
      rescue => e
        p "%" * 40
        p person
        p "%" * 40
        raise e
      end

      # users テーブルを id を指定して作成したのでシーケンスの値を手動で更新します
      con = ActiveRecord::Base.connection
      con.execute("select setval('users_id_seq', coalesce((select max(id)+1 from users), 1), false)")

      Participant.find_each do |participant|
        Teammate.create!(
          event_id: participant.event_id,
          user_id: participant.person_id,
          role: participant.role,
          email: participant.person.email,
          state: "accepted",
          accepted_at: Time.current
        )
      end

      Rating.find_each do |r|
        r.user_id = r.person_id
        r.save!
      end

      # person_idがnilなレコードがあるのでそれは無視します
      # ToDo アカウントが生成されたなかった場合を考慮する
      # Speaker.where.not(person_id: [nil, 171, 172]).find_each do |s|
      Speaker.where.not(person_id: nil).find_each do |s|
        s.user_id = s.person_id
        s.event_id = s.proposal.event.id
        s.speaker_name = s.user.name
        s.speaker_email = s.user.email
        s.save!
        rescue => e
          p "%" * 10
          p s
          p "%" * 10
          raise e
      end

      # 171, 172の方はそれぞれ 179, 252と同一のアカウントとなっている、かつログインできるアカウントも後者のidです
      # それぞれに紐付いている、Proposalを移行します
      [[171, 179], [172, 252]].each do |from, to|
        Person.find(from).speakers.each do |s|
          s.user_id = to
          s.save!
        end
      end

      # Comment.where.not(person_id: [5]).find_each do |c|
      Comment.find_each do |c|
        c.user_id = c.person_id
        c.save!
        rescue => e
          p "%" * 10
          p c
          p "%" * 10
          raise e
      end
    end
  end
end
