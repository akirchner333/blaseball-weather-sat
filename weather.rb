require 'net/http'
require 'uri'
require 'json'
require 'twitter'

# Pulls all the games for a given day and season from the blaseball API
def getGames(season, day)
  queryAPI("https://www.blaseball.com/database/games?day=#{day}&season=#{season}")
end

# A general function for querying a url and getting back a JSON response
def queryAPI(url)
  uri = URI(url)

  Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
    request = Net::HTTP::Get.new uri
    response = http.request request
    JSON.parse(response.body)
  end
end

# The bot posts a team every 20 minutes and uses place.txt to remember which team it posted last
# It pulls an index from the file and then saves the next index
def getPlace
  File.open("place.txt", "r+") do |file|
    number = file.gets.to_i
    file.seek(0)
    file.puts((number + 1) % 25)
    number
  end
end

# Pulls all the teams
# the /allTeams end point in the blaseball api includes every team, including inactive ones
# Currently I'm detecting if a team is active based on if it has a stadium or not
# No doubt I will have to keep updating this function as new teams with weird traits are introduced
def getTeams
  queryAPI("https://www.blaseball.com/database/allTeams")
    .select { |team| !team["stadium"].nil? } 
    .sort_by{ |team| team["id"]}
end

# The generates the text of the tweet
def generateTweet
  now = queryAPI("https://www.blaseball.com/database/simulationData")

  return false unless now['phase'] == 2 || now['phase'] == 4 || now['phase'] == 6

  teams = getTeams
  team = teams[getPlace]

  if !team.nil?
    forecast(now["season"], now["day"], team["location"], team["id"])
  else
    # I've always include a forecast from one additional place other than the teams
    # Currently it's blaseball zero, which is full of tumbleweed
    forecast = "7 DAY WEATHER FORECAST FOR BLASEBALL ZERO\n"
    7.times do |i|
      forecast += "Day #{now["day"] + i}: TUMBLEWEED\n"
    end
    forecast
  end
end

# Generates a forecast for a team
def forecast(season, day, location, team)
  forecast = "7 DAY WEATHER FORECAST FOR #{location.upcase}\n"

  7.times do |i|
    games = getGames(season, day + i)
    game = games.find {|g| g["homeTeam"] == team}
    if game.nil?
      # If nobody is playing at a given location, there's no weather
      forecast += dayReport(day, i, "Nothing")
    else
      w = game["weather"]
      forecast += dayReport(day, i, getWeather(w))
    end
  end
  forecast
end

# A list of weather types
# The 'seen' specifies if that kind of weather has ever been seen in game before
# Weather that hasn't been seen won't be picked for fake weather events
def weatherTypes
  weatherTypes = [
    {gameName: "Void", name: ["Void"], seen: false},
    {gameName: "Sun 2", name: ["Sun 2", "The New Sun", "Sunny"], seen: true},
    {gameName: "Overcast", name: ["Clouds"], seen: false},
    {gameName: "Rainy", name: ["Rain"], seen: false},
    {gameName: "Sandstorm", name: ["Sand"], seen: false},
    {gameName: "Snowy", name: ["Snow"], seen: false},
    {gameName: "Acidic", name: ["Acid"], seen: false},
    {gameName: "Solar Eclipse", name: ["Solar Eclipse", "Darkness"], seen: true},
    {gameName: "Glitter", name: ["Glitter", "Sparkles"], seen: true},
    {gameName: "Blooddrain", name: ["Blooddrain", "Blood"], seen: true},
    {gameName: "Peanuts", name: ["Peanuts", "A Bunch Of Peanuts"], seen: true},
    {gameName: "Lots of Birds", name: ["Birds", "Lots of Birds", "Just So Many Birds"], seen: true},
    {gameName: "Feedback", name: ["Feedback", "Deafening Feedback"], seen: true},
    {gameName: "Reverb", name: ["Reverb", "Brever"], seen: true},
    {gameName: "Black Hole", name: ["Black Hole", "Gravitational Anomalies"], seen: true},
    {gameName: "Coffee", name: ["Coffee"], seen: true},
    {gameName: "Coffee 2", name: ["Coffee 2"], seen: true},
    {gameName: "Coffee 3s", name: ["Coffee 3s"], seen: true},
    {gameName: "Flooding", name: ["Flooding", "Water", "Wet"], seen: true},
    {gameName: "Salmon", name: ["Salmon", "Fish"], seen: true},
    {gameName: "Polarity +", name: ["Polarity +", "Polarity Plus", "Numbers Up"], seen: true},
    {gameName: "Polarity -", name: ["Polarity -", "Polarity Minus", "Numbers Down"], seen: true},
    {gameName: "???", name: ["???"], seen: false},
    {gameName: "Sun90", name: ["Sun90"], seen: false},
    {gameName: "Sun .1", name: ["Sun 0.1", "Sun .1", "Tiny Sun", "Slightly Sunny"], seen: true},
    {gameName: "Sum Sun", name: ["Sum Sun"], seen: false},
    {gameName: "Jazz", name: ["Jazz"], seen: false},
    {gameName: "Night", name: ["Night"], seen: true}
  ]
end

# Gets weather by index
def getWeather(index)
  weatherTypes[index][:name].sample
end

# Returns all the weather we've seen before
def seenWeather
  weatherTypes.select {|weather| weather[:seen]}
end

# Random weather from the weather we've seen before
def randomWeather
  seenWeather.sample[:name].sample
end

# Forecasts are generated as follows:
# The chance a weather forecast will be correct depends on how far out it is, based on this table:
# Day +0 (today): 100%
# Day +1 (tomorrow): 100%
# Day +2: 80 - 60
# Day +3: 70 - 50
# Day +4: 60 - 40
# Day +5: 50 - 30
# Day +6: 40 - 20
# We generate a random number which is the chance we're going to print
# And then a second random number - if it's below the chance we tell the truth, above we lie.
def dayReport(day, offset, weather)
  p "#{day}, #{offset}, #{weather}"
  if offset < 2
    "Day #{day + offset + 1}: #{weather}\n"
  else
    falseWeather = randomWeather
    odds = rand(30) + (6 - offset) * 10 + 10
    "Day #{day + offset + 1}: #{odds}\% Chance of #{pickPrediction(odds, weather, falseWeather)}\n"
  end
end

def pickPrediction(odds, truth, falsehood)
  rand(100) < (odds) ? truth : falsehood
end

def post
  client = Twitter::REST::Client.new do |config|
    config.consumer_key         = "CONSUMER_KEY"
    config.consumer_secret      = "CONSUMER_SECRET"
    config.access_token         = "ACCESS_TOKEN"
    config.access_token_secret  = "ACCESS_TOKEN_SECRET"
  end

  tweet = generateTweet
  p tweet
  client.update(tweet) if tweet
end

post
