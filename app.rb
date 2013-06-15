require "sinatra"
require "rest-client"
require "nokogiri"
require "json"

require "pry"
require "pry-debugger"
require "pry-stack_explorer"

LIFE_EXPECTANCY_FILENAME = "life_expectancy_data.json"

helpers do
  def api_endpoint
    "http://shin-ny.herokuapp.com"
  end

  def api_get(path)
    RestClient.get "#{api_endpoint}#{path}"
  end
end

get "/" do
  """
  <html>
    <head>
      <title>Not a useful page.</title>
    </head>
    <body>
      <p>You can do anything... at Diablo Beats.</p>
    </body>
  </html>
  """
end

# Returns age, sex, smoking status, HBA1c, HDL cholesterol, systolic blood
# pressure, BMI, and life expectancy for the supplied patient. Patient must be
# fully specified by id and case-sensitive name, where the name is provided as
# a querystring parameter: /patients/1?name=John+Smith
get "/patients/:id/?" do
  xml_string = api_get "/patients/#{params[:id]}"
  xml = Nokogiri::XML xml_string

  patient_node = xml.css "patient"

  patient = {}
  patient[:givenName] = patient_node.css("name given text()").to_s
  patient[:familyName] = patient_node.css("name family text()").to_s

  # Dmitry Tsatsulin
  if params[:name] != [patient[:givenName], patient[:familyName]].join(" ")
    403
  else
    birth_year = patient_node.css("birthTime")[0]["value"][0...4].to_i
    patient[:age] = Time.now.year - birth_year

    patient[:sex] = patient_node.css("administrativeGenderCode")[0]["code"] == "M" ? "m" : "f"

    interim_node = xml.css("code[displayName='Systolic'] translation[code='SYSTOLIC']")[0]
    systolic = interim_node.parent.parent.css("value")[0]["value"].to_f # float so we can mega-round

    systolic = ((systolic / 20).round * 20).to_i

    if systolic < 120
      systolic = 120
    elsif systolic > 180
      systolic = 180
    end

    patient[:systolic] = systolic

    dummy_node = xml.css("dummyData")
    patient[:totalHDL] = dummy_node.css("totalHDL text()").to_s.to_i
    patient[:bmi] = dummy_node.css("bmi text()").to_s.to_i
    patient[:smoker] = dummy_node.css("smoker text()").to_s == "true"

    # mystic runes
    interim_node = xml.css("code[code='17856-6']")[0]
    hba1c = interim_node.parent.css("value")[0]["value"].to_f
    hba1c = (hba1c / 2).round * 2

    if hba1c < 6
      hba1c = 6
    elsif hba1c > 10
      hba1c = 10
    end

    patient[:hba1c] = hba1c

    # look up life expectancy based on the six discriminators
    life_expectancy = JSON.load File.open(LIFE_EXPECTANCY_FILENAME)

    # coerce patient[:age] to something we have data for in order to look up an entry!

    age_adjustment = 0
    age_for_calculations = 0

    [75, 65, 55].each do |age|
      if patient[:age] < age
        age_adjustment = age - patient[:age]
        age_for_calculations = age
      end
    end

    entry = life_expectancy
      .select {|e| e["age"] == age_for_calculations}
      .select {|e| e["sex"] == patient[:sex]}
      .select {|e| e["smoker"] == patient[:smoker]}
      .select {|e| e["systolic"] == patient[:systolic]}
      .select {|e| e["totalHDL"] == patient[:totalHDL]}
      .select {|e| e["hba1c"] == patient[:hba1c]}
      .last

    binding.pry

    patient[:life] = entry["life"] + age_adjustment

    patient.to_json
  end
end
