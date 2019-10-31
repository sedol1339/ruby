#чтение файла

lines = File.readlines('apache_log.txt')
puts "-------------------------------------------"
puts "File contains #{lines.length} lines"

#разбор строк

require 'date'
entries = lines.map.each_with_index do |line, i|
	match = line.match(/(?<ip>[^ ]*) - - \[(?<time>[^\]]*)\] (?<content>.*)/)
	#мне лень проверять в документации, не осуществляет ли строка выше компиляцию
	#регулярного выражения каждую итерацию цикла; по идее не должна
	if not match
		puts "Cannot parse line ##{i}: " + line
		next
	end
	ip = match[:ip]
	time_str = match[:time]
	content = match[:content]
	
	#trying to parse time string
	begin
		time = DateTime.strptime( time_str, "%d/%b/%Y:%H:%M:%S %Z")
	rescue ArgumentError => exception
		puts "#{exception} #{match[:time]}"
		next
	end
	
	#parsing content
	match2 = content.match(/"(?<request>[^"]*)" (?<status>[^ ]+) (?<size>[^ ]+) "(?<referer>[^"]*)" "(?<useragent>[^"]*)"/)
	if not match2
		puts "Cannot parse content at line ##{i}: " + content
		next
	end
	request = match2[:request]
	status_str = match2[:status]
	size_str = match2[:size]
	referer = match2[:referer]
	useragent = match2[:useragent]
	
	#converting status and size to integer
	begin
		status = Integer(status_str)
		size = (size_str == "-") ? -1 : Integer(size_str)
	rescue ArgumentError => exception
		puts "#{exception} when converting status and date to int while parsing string ##{i}"
	end
	
	#parsing request
	match3 = request.match(/(?<method>[^ ]*) (?<url>[^ ]*) (?<protocol>[^ ]*)/)
	if not match3
		puts "Cannot parse request at line ##{i}: " + request
		next
	end
	method = match3[:method]
	url = match3[:url]
	protocol = match3[:protocol]
	
	#saving
	next {
		"ip" => ip,
		"time" => time,
		"method" => method,
		"url" => url,
		"protocol" => protocol,
		"status" => status,
		"size" => size,
		"referer" => referer,
		"useragent" => useragent,
	}
end
entries.compact!
puts "#{entries.length} lines parsed"
puts "example of parsed line:"
require 'json'
puts JSON.pretty_generate(entries[0])

#анализ
puts "-------------------------------------------"

#создаем словарь ip -> количество_обращений
requests_by_ip = Hash.new(0)
entries.each do |elem|
	requests_by_ip[elem["ip"]] += 1
end
requests_by_ip = requests_by_ip.sort_by { |_key, value| value }
requests_by_ip.reverse!

#печатаем ip с максимальным количеством обращений
puts "IP with max requests:"
requests_by_ip[0..10].each do |elem|
	puts elem[0] + " - #{elem[1]} requests"
end

puts ""

#создаем словарь метод -> количество_обращений
requests_by_method = Hash.new(0)
entries.each do |elem|
	requests_by_method[elem["method"]] += 1
end
requests_by_method = requests_by_method.sort_by { |_key, value| value }
requests_by_method.reverse!

#печатаем методы и количество обращений
puts "Methods and requests amount:"
requests_by_method.each do |elem|
	puts elem[0] + " - #{elem[1]} requests"
end

puts ""

#создаем словарь useragent -> количество_обращений
requests_by_agent = Hash.new(0)
entries.each do |elem|
	useragent = elem["useragent"].split(" ")[0]
	requests_by_agent[useragent] += 1
end
requests_by_agent = requests_by_agent.sort_by { |_key, value| value }
requests_by_agent.reverse!

#печатаем агенты и количество обращений
puts "Useragents (up to first whitespace) with 2+ requests and requests amount:"
requests_by_agent.each do |elem|
	if elem[1] < 2 then break end
	puts elem[0] + " - #{elem[1]} requests"
end