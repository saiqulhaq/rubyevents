desc "Set speakerdeck name from slides_url"
task set_speakerdeck_name_from_slides_url: :environment do |t, args|
  users = User.distinct.where(speakerdeck: "").where.associated(:talks)
  updated = 0

  puts "Found #{users.count} speakers with no speakerdeck name"

  users.find_in_batches do |users|
    users.each do |user|
      speakerdeck_name = user.speakerdeck_user_from_slides_url

      if speakerdeck_name
        user.update!(speakerdeck: speakerdeck_name)
        puts %(Updating "#{user.name}" (id: #{user.id}) with Speakerdeck name "#{user.speakerdeck_user_from_slides_url}")
        updated += 1
      end
    end
  end

  puts "Updated #{updated} users"
end
