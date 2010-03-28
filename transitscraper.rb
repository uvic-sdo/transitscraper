require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'pp'

require "active_record"

ActiveRecord::Base.logger = Logger.new(STDERR)
ActiveRecord::Base.colorize_logging = true

ActiveRecord::Base.establish_connection(
	:adapter  => "sqlite3",
	:database => "bus.db"
	#:database => ":memory:"
)

ActiveRecord::Schema.define do
	create_table :routes, :primary_key => "id" do |t|
		t.column :number, :string
		t.column :name, :string
	end
	create_table :stops, :primary_key => "id" do |t|
		t.column :name, :string
	end
	create_table :sched_times, :primary_key => "id" do |t|
		t.column :time, :integer
		t.column :day, :integer
		t.column :direction, :integer
		t.column :route_id, :integer
		t.column :stop_id, :integer
	end

end

class Stop < ActiveRecord::Base
	set_primary_key 'id'
	has_many :sched_times
	def self.get name
		Stop.find_by_name(name) || Stop.create(:name=>name)
	end
end
class Route < ActiveRecord::Base
	set_primary_key 'id'
	has_many :sched_times
end
class SchedTime < ActiveRecord::Base
	set_primary_key 'id'
	belongs_to :route
	belongs_to :stop
end
 
BASE_URL='http://www.bctransit.com/regions/vic/'
index = Nokogiri::HTML(open(BASE_URL))

test = []

lines = index.css('#dvSchedule a').map do |item|
	if item[:href] =~ /\/regions\/vic\/schedules\/schedule\.cfm\?line=(\d+)&/
		[$1, item.children.to_xml]
	end
end.uniq.compact

def fetchroute route, direction, day
	url = "#{BASE_URL}schedules/schedule.cfm?p=dir.text&route=#{route.number}:#{direction}&day=#{day}"
	puts url
	line = Nokogiri::HTML(open(url))
	#title = line.at_css('b.css-header-title').children[0].to_xhtml
	table = line.at_css('.scheduletable')
	return if table.nil?
	points = table.css('.css-sched-waypoints').map{|n| n.children[0].to_xml}
	return if points.nil?
	points = points.uniq[1,10000]

	times = line.css('.css-sched-times').map{|n| n.children[0].to_xml}.reject{|x| x == "&#xA0;"}
	return if times.nil?

	points.map! { |p| Stop.get(p).id }
	lasttimes = [0]*points.length
	offsets = [0]*points.length

	numstops = points.length + 1
	(times.length).times do |j|
		next if j % numstops == 0
		i = j % numstops - 1
		if times[j] =~ /([0-9][0-9]?):([0-9][0-9])/
			time = ($1 == "12" ? 0 : $1.to_i) * 60 + $2.to_i
			offsets[i] = 12*60 if time < lasttimes[i]
			time += offsets[i]
			lasttimes[i] = time
			SchedTime.create(:route=>route, :stop_id=>points[i], :day=>day, :direction=>direction, :time=>time)
		end
	end
end

def fetchline lineno, name
	puts "fetching line #{lineno}"
	r = Route.create(:number=>lineno, :name=>name)
	for direction in [0,1] do
		for day in [1,6,7] do
			# this speeds up sqlite a TON
			ActiveRecord::Base.transaction do
				fetchroute r, direction, day
			end
		end
	end
end

lines.each { |lineno, name| fetchline(lineno, name) }

