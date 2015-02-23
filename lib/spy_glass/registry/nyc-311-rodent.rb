require 'spy_glass/registry'

time_zone = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]

opts = {
  path: '/nyc-311-rodent',
  cache: SpyGlass::Cache::Memory.new(expires_in: 300),
  source: 'http://data.cityofnewyork.us/resource/erm2-nwe9.json?'+Rack::Utils.build_query({
    '$limit' => 1000,
    '$order' => 'created_date DESC',
    '$select' => 'address_type,city,closed_date,created_date,cross_street_1,cross_street_2,descriptor,incident_address,intersection_street_1,intersection_street_2,latitude,location_type,longitude,status,street_name,unique_key',
    '$where' => <<-WHERE.oneline
      created_date >= '#{7.days.ago.iso8601}' AND
      complaint_type = 'Rodent' AND
      longitude IS NOT NULL AND
      latitude IS NOT NULL AND
      unique_key IS NOT NULL
    WHERE
  })
}

SpyGlass::Registry << SpyGlass::Client::Socrata.new(opts) do |collection|
  features = collection.map do |item|

    DATE_FORMAT = "%a %b %-d"   # ignore time, all complaintes arrive at 12:00:00 am (?)

    if item['created_date'].length > 0 then
      created = Time.iso8601(item['created_date']).in_time_zone(time_zone).strftime(DATE_FORMAT)
    else
      created = "at some point this week"
    end

    city = item['city']
    address =
      case item['address_type']
      when 'ADDRESS'
        "at #{item['incident_address'].titleize} in #{city.capitalize}."
      when 'INTERSECTION'
        intersection_street_1 = item['intersection_street_1']
        intersection_street_2 = item['intersection_street_2']
        "at the intersection of #{intersection_street_1.titleize} and #{intersection_street_2.titleize} in #{city.capitalize}."
      when 'BLOCKFACE'
        cross_street_1 = item['cross_street_1']
        cross_street_2 = item['cross_street_2']
        street = item['street_name']
        "on #{street.titleize}, between #{cross_street_1.titleize} and #{cross_street_2.titleize} in #{city.capitalize}."
      else
        "on #{item['street_name']} in #{city}."
      end

    if item['status'] == 'Closed' then
      closed = Time.iso8601(item['closed_date']).in_time_zone(time_zone).strftime(DATE_FORMAT)
      title = "Closed #{item['descriptor']} #{address} originally called in on #{created} was closed on #{closed}."
    else
      title = "#{item['descriptor']} #{address} called in on #{created}."
    end

    {
      'id' => item['unique_key'],
      'type' => 'Feature',
      'geometry' => {
        'type' => 'Point',
        'coordinates' => [
          item['longitude'].to_f,
          item['latitude'].to_f
        ]
      },
      'properties' => item.merge('title' => title)
    }
  end

  {'type' => 'FeatureCollection', 'features' => features}
end

