#ТЕСТЫ

$examples = [ #length, symbols, md5 of output_array.sort.to_s
	[0, 'a'..'c', 'd751713988987e9331980363e24189ce'],
	[5, ['a'], 'd751713988987e9331980363e24189ce'], 
	[1, ['a'], '4c96bbc0e2390918dd50ef8e7eaff6e2'],
	[5, ['a', 'b'], '5175ce212d34711fa96f1175c05b1bf7'],
	[3, 'a'..'c', '51f113d11fac0b4310dcf5ff888d72c7'],
	[1, 'A'..'Q', 'c3270d357c556d66b6ba79da1cf7a516'],
]

$benchmark = [11, 'a'..'d']
$benchmark_iterations = 10

require 'digest/md5'

def examples_test(name = nil)
	puts(name) if name
	$examples.each do |example|
		arr = yield(example[0], example[1])
		md5_of_sorted_array = Digest::MD5.hexdigest(arr.sort.to_s)
		passed = (md5_of_sorted_array == example[2])
		puts "#{ example[0] }, #{ example[1] }:".ljust(20) \
			 + (if passed then "PASSED" else "FAILED" end) + " " \
			 + arr.to_s
	end
end

def performance_test(name = nil)
	puts(name) if name
	print "#{ $benchmark[0] }, #{ $benchmark[1] }:".ljust(20) + "Подождите... "
	performance_times = []
	len = 0
	$benchmark_iterations.times do
		start = Time.now
		len = yield($benchmark[0], $benchmark[1])
		performance_times.push(Time.now - start)
	end
	avg_time = performance_times.inject{ |sum, el| sum + el }.to_f / performance_times.size
	puts "Сгенерировано #{ len } строк в среднем за #{ (1000 * avg_time).round(1) } мс"
end

puts "-" * 50



#--------------------------------------------------------------
#ВАРИАНТ 1 - самый простой, с рекурсией
#--------------------------------------------------------------

def generate(n, _symbols)
	symbols = _symbols.to_a
	return [] if n == 0
	return symbols.clone if n == 1
	arr = []	#all valid strings of length n
	for str in generate(n - 1, symbols)	#all valid strings of length n-1
		for symbol in symbols
			if symbol != str[-1]
				arr.push(str + symbol)
			end
		end
	end
	return arr
end

#проверка

examples_test("\nВАРИАНТ 1 - самый простой, с рекурсией") do |n, symbols|
	generate(n, symbols)
end

performance_test do |n, symbols|
	generate(n, symbols).length
end



#--------------------------------------------------------------
#ВАРИАНТ 2 - такой же, но с each вместо for
#--------------------------------------------------------------

def generate(n, _symbols)
	symbols = _symbols.to_a
	return [] if n == 0
	return symbols.clone if n == 1
	arr = []
	generate(n - 1, symbols).each { |str|
		symbols.each { |symbol|
			if symbol != str[-1]
				arr.push(str + symbol)
			end
		}
	}
	return arr
end

#проверка

examples_test("\nВАРИАНТ 2 - такой же, но с each вместо for") do |n, symbols|
	generate(n, symbols)
end

performance_test do |n, symbols|
	generate(n, symbols).length
end



#--------------------------------------------------------------
#ВАРИАНТ 3 - с генератором вместо построения массива целиком
#--------------------------------------------------------------

'''class Generator < Enumerator
	def initialize(n, _symbols)
		@n = n
		@symbols = _symbols.to_a
		@str = @symbols[0] * n
		@size = @symbols.length
		@indices = Array.new(n, 0)
	end
end

p Generator.new(n, symbols).to_a'''

def generate(n, _symbols)
	symbols = _symbols.to_a
	str = symbols[0] * n
	base = symbols.length
	#мы будем рассматривать строку как число
	#в системе счисления разрядности symbols.length
	if base == 1 and n == 1
		yield symbols[0]
		return
	elsif base < 2 || n < 1
		return
	end
	str = symbols[0] * n
	indices = Array.new(n, 0)
	value = 0
	(0..n-1).each do |i|
		indices[i] = value
		str[i] = symbols[value]
		value = (value + 1) % 2
	end
	yield str
	loop do
		inc_index = 0
		(n-1).downto(0).each do |i|
			inc_index = i
			if indices[i] == base-1
				return if i == 0
				next
			elsif i != 0 and indices[i-1] == indices[i] + 1
				#прибавляем 2
				if indices[i] == base-2
					next
				else
					new_index = (indices[i] += 2)
					str[i] = symbols[new_index]
					break
				end
			else
				#прибавляем 1
				new_index = (indices[i] += 1)
				str[i] = symbols[new_index]
				break
			end
		end
		#inc_index - индекс, где произошло увеличение на 1
		#сбрасываем все следующие индексы до минимально допустимого значения (0-1-0-1-...)
		new_value = 0
		(inc_index+1..n-1).each do |i|
			indices[i] = new_value
			str[i] = symbols[new_value]
			new_value = (new_value + 1) % 2
		end
		yield str
	end
end

#проверка

examples_test("\nВАРИАНТ 3 - с генератором вместо построения массива целиком") do |n, symbols|
	arr = []
	generate(n, symbols) { |str| arr.push(str.clone) }
	arr
end

performance_test do |n, symbols|
	count = 0
	generate(n, symbols) { count += 1 }
	count
end



#--------------------------------------------------------------
#ВАРИАНТ 4 - с функцией repeated_permutation
#--------------------------------------------------------------

def valid?(str)
	(1...str.length).each do |i|
		return false if str[i] == str[i-1]
	end
end

def generate(n, _symbols)
	symbols = _symbols.to_a
	return [] if n < 1
	symbols
		.repeated_permutation(n) # <- это очень медленная операция
		.select{ |str| valid? str }
		.map(&:join)
		.to_a
end

#проверка

examples_test("\nВАРИАНТ 4 - с функцией repeated_permutation") do |n, symbols|
	generate(n, symbols)
end

performance_test do |n, symbols|
	generate(n, symbols).length
end



#--------------------------------------------------------------
#ВАРИАНТ 5 - как второй, но с распараллеливанием по первой букве
#--------------------------------------------------------------

#gem install parallel-each
require 'parallel_each'

def generate(n, _symbols, recursive_call = false)
	symbols = _symbols.to_a
	return [] if n == 0
	return symbols.clone if n == 1
	substr = generate(n - 1, symbols, true)
	
	extend_str = lambda do |symbol, _arr|
		substr.each do |str|
			if symbol != str[0]
				_arr.push(symbol + str)
			end
		end
	end
	
	if recursive_call
		#не распараллеливаем
		arr = []
		symbols.each do |symbol|
			extend_str.(symbol, arr)
		end
		return arr
	else
		#распараллеливаем
		threads = []
		arrays = Array.new(symbols.length) { [] }
		symbols.each_with_index do |symbol, index|
			threads << Thread.new do
				extend_str.(symbol, arrays[index])
			end
		end
		threads.each(&:join)
		return arrays.reduce([], :concat)
	end
end

#проверка

examples_test("\nВАРИАНТ 5 - как второй, но с распараллеливанием по первой букве") do |n, symbols|
	generate(n, symbols)
end

performance_test do |n, symbols|
	generate(n, symbols).length
end

#---------------------------------------------------

#gem install newrelic_rpm
#gem install get_process_mem
#gem install sys-proctable
#require 'newrelic_rpm'
#require 'get_process_mem'
#p NewRelic::Agent::Samplers::MemorySampler.new.sampler.get_sample
#p GetProcessMem.new.mb

#require 'benchmark'

#Benchmark.bm do |performance|
#   performance.report("Время: "){ 1000000.times{ a=[]; a << 5}}
#end