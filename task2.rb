'''нам не следует наследовать новый класс от Array (ArrayParallel < Array)
проблема в том, что следующие вызовы:
ArrayParallel.new.to_a, ArrayParallel.new.reverse и прочие
вернут Array, если не переопределять эти методы
чтобы решить эту проблему, надо переопределять много методов, например:
	def reverse
		return ArrayParallel.new(super.reverse)
	end
но тогда в методе reverse происходит копирование массива - лишняя операция
https://words.steveklabnik.com/beware-subclassing-ruby-core-classes'''

class ArrayParallel

	def initialize(*args, &block)
		if args.length == 1 and args[0].is_a?(Array)
			@_arr = args[0]
		else
			@_arr = Array.new(*args, &block)
		end
	end
	
	def __get_array__
		@_arr
	end
	
	##################################
	
	MIN_ELEMENTS_FOR_THREAD = 1000
	MAX_THREADS = 4
	
	def __make_splitting_for_multithreading
		#returns array of [start, end] inclusive
		size = @_arr.length
		threads = [1, size / 1000].max #returns int (floor)
		threads = [threads, MAX_THREADS].min
		block_size = size / threads
		result = Array.new
		elem_after_last_end = 0
		(1..threads).each do |i|
			current_end = [block_size * i, size - 1].min
			result << [elem_after_last_end, current_end]
			elem_after_last_end = current_end + 1
		end
		return result
	end
	
	##################################
	
	def map(&block)
		if block
			#многопоточность используется только в случае, если map вызывается с блоком, потому что
			#в противном случае map должен вернуть итератор, а я не могу представить итератор, который
			#бы работал в многопоточном режиме
			return map_or_select_multithreaded(false, &block)
		end
		enum = Enumerator.new do |yielder|
			new_arr = ArrayParallel.new
			@_arr.each do |elem|
				new_arr << (yielder.yield elem)
			end
			new_arr
		end
		return enum
	end
	
	def select(&block)
		if block
			return map_or_select_multithreaded(true, &block)
		end
		enum = Enumerator.new do |yielder|
			new_arr = ArrayParallel.new
			@_arr.each do |elem|
				if yielder.yield elem
					new_arr << elem
				end
			end
			new_arr
		end
		return enum
	end
	
	def map_or_select_multithreaded(select, &block) #block is not null
		#если select = true то метод select, иначе метод map
		#мы не можем вызывать map для подмассивов @_arr[start, end], потому что
		#при создании массива вероятно происходит копирование всех элементов
		#в гугле отсутствуют ответы на вопрос "ruby create|iterate subarray without copying"
		#поскольку в программировании все вопросы решаются через гугл, это говорит о том,
		#что вопрос этот не решается, и делать итерацию по подмассиву без копирования нельзя
		#копирование же совершенно бессмысленно и снижает производительность
		#--------------------------------------------
		#---------------- ¯\_(ツ)_/¯ -----------------
		#--------------------------------------------
		splitting = __make_splitting_for_multithreading()
		amount_of_threads = splitting.length
		result_arrays = Array.new(splitting.length) do
			Array.new
		end
		proc_for_each_thread = Proc.new do |thread_number| #inclusive
			range = splitting[thread_number]
			array = result_arrays[thread_number]
			if select
				for_each_elem = Proc.new do |i|
					elem = @_arr[i]
					if block.call(elem)
						array << elem
					end
				end
			else
				for_each_elem = Proc.new do |i|
					elem = @_arr[i]
					array << block.call(elem)
				end
			end
			(range[0]..range[1]).each(&for_each_elem)
		end
		threads = []
		(1...amount_of_threads).each do |i|
			#proc_for_each_thread.call(i)
			threads << Thread.new(i, &proc_for_each_thread)
		end
		proc_for_each_thread.call(0)
		threads.each do |thread|
			thread.join
		end
		ArrayParallel.new(result_arrays.reduce([], :concat))
	end
	
	##################################
	
	def any?(*args, &block)
		if block
			return any_multithreaded?(*args, &block)
		end
		@_arr.any?(*args)
	end
	
	ANY_DEBUG = true
	
	def any_multithreaded?(*args, &block)
		#если элемент, соответствующий требуемому в условии, найден, то следует
		#завершить все потоки, а если в главном потоке завершить цикл
		splitting = __make_splitting_for_multithreading()
		amount_of_threads = splitting.length
		threads = []
		thread_main = Thread.current
		result = false
		proc_for_each_thread = Proc.new do |thread_number| #inclusive
			range = splitting[thread_number]
			proc = nil
			if args.length == 1
				proc = Proc.new { |obj| args[0] === obj } #согласно документации
			elsif args.length == 0
				proc = block ? block : Proc.new { |obj| obj } #согласно документации
			else
				raise ArgumentError.new("wrong number of arguments (given #{args.length}, expected 0..1)")
			end
			(range[0]..range[1]).each do |i|
				elem = @_arr[i]
				_result = proc.call(elem)
				if _result != false and _result != nil
					if ANY_DEBUG then puts "thread #{thread_number} found element" end
					result = true
					threads.each do |thread|
						if thread != Thread.current and thread != thread_main
							if ANY_DEBUG then  puts "terminating thread..." end
							thread.terminate
						end
					end
					break
				end
				if i%100 == 0 and result
					#this can happen only in thread_main, others are ternimated after result becomes true
					break
				end
			end
		end
		(1...amount_of_threads).each do |i|
			threads << Thread.new(i, &proc_for_each_thread)
		end
		proc_for_each_thread.call(0)
		if ANY_DEBUG then puts "thread 0 stopped iteration" end
		threads.each do |thread|
			#this can happen when main thread finishes iteration with false result
			#while other threads are still iterating
			thread.join
		end
		if ANY_DEBUG then  puts "all threads finished" end
		result
	end
	
	def all?(*args, &block)
		#многопоточность реализуется аналогично "any?"
		#стоит использовать код any, добавив в него один аргумент:
		#def any_multithreaded?(__from_all, *args, &block)
		#который изменяет логику работы некоторых выражений
		#однако это приведет к снижению читаемости метода any_multithreaded
		#поэтому я не реализовал эту возможность
		@_arr.all?(*args, &block)
	end
	
	##################################
	
	def to_s
		@_arr.to_s
	end
	
	def to_a
		self
	end
	
	def to_ary
		self 
	end
	
	def self.[](*args) #ArrayParallel.[]('a', 'b', 'c')
		ArrayParallel.new(args)
	end
	
	def &(other_ary) #Array or ArrayParallel
		if other_ary.is_a?(ArrayParallel)
			ArrayParallel.new(@_arr & other_ary.__get_array__)
		else #Array or convertable
			ArrayParallel.new(@_arr & other_ary.to_a)
		end
	end
	
	def *(param) #int or string
		if param.is_a?(String)
			join(param)
		else #Integer or convertable
			ArrayParallel.new(@_arr * int.to_i)
		end
	end
	
	def +(other_ary) #Array or ArrayParallel
		if other_ary.is_a?(ArrayParallel)
			ArrayParallel.new(@_arr + other_ary.__get_array__)
		else #Array or convertable
			ArrayParallel.new(@_arr + other_ary.to_a)
		end
	end
	
	def -(other_ary) #Array or ArrayParallel
		if other_ary.is_a?(ArrayParallel)
			ArrayParallel.new(@_arr - other_ary.__get_array__)
		else #Array or convertable
			ArrayParallel.new(@_arr - other_ary.to_a)
		end
	end
	
	def <<(obj)
		@_arr << obj
		self
	end
	
	def <=>(other_ary) #Array or ArrayParallel
		if other_ary.is_a?(ArrayParallel)
			@_arr <=> other_ary.__get_array__
		else #Array or convertable
			@_arr <=> other_ary.to_a
		end
	end
	
	def ==(other_ary) #Array or ArrayParallel
		if other_ary.is_a?(ArrayParallel)
			@_arr == other_ary.__get_array__
		else #Array or convertable
			@_arr == other_ary.to_a
		end
	end
	
	def [](*args)
		result = @_arr[*args]
		if result.is_a?(Array)
			ArrayParallel.new(result)
		else
			result
		end
	end
	
	alias slice []
	
	def []=(*args)
		#преобразуем ArrayParallel в параметрах в Array
		if args[1].is_a?(ArrayParallel)
			args[1] = args[1].__get_array
		end
		if args[2].is_a?(ArrayParallel)
			args[2] = args[2].__get_array
		end
		#@_arr.[]= (*args)
		@_arr.method( :[]= ).call(*args)
	end
	
	def assoc(obj)
		@_arr.assoc(obj)
	end
	
	def at(index)
		@_arr.at(index)
	end
	
	def bsearch(&block)
		@_arr.bsearch(&block)
	end
	
	def bsearch_index(&block)
		@_arr.bsearch_index(&block)
	end
	
	def clear
		@_arr.clear
	end
	
	'''
	include Enumerable
	
	#this provides methods each, any?, all?, collect and more
	#https://ruby-doc.org/core-2.6.3/Enumerable.html
	
	#не работает! например, collect возвращает Array, а не ArrayParallel
	
	def each(&block)
		@_arr.each(&block)
	end
	'''
	
	def map!(&block)
		enum = Enumerator.new do |yielder|
			@_arr.each_with_index do |elem, index|
				@_arr[index] = yielder.yield elem
			end
			self #не спрашивайте почему, я танцевал с бубном
		end
		return enum unless block
		enum.each(&block)
	end
	
	alias collect map
	
	alias collect! map!
	
	#def each(&block)
	#	@_arr.each(&block)
	#end
	#Мы не можем так сделать, потому что конструкция
	#arrayParallel.each.with_index {|x, i| #... }
	#вернет Array, а должна возвращать ArrayParallel
	#для использования в цепочках
	
	def each(&block)
		enum = Enumerator.new do |yielder|
			#@_arr.each do |elem|
			#	yielder.yield elem
			#end
			@_arr.each &:yielder.yield
			self
		end
		return enum unless block
		enum.each(&block)
	end
	
	def combination(n, &block)
		enum = Enumerator.new do |yielder|
			new_arr = ArrayParallel.new
			_arr_enum = @_arr.combination(n)
			loop do
				begin
					new_arr << (yielder.yield _arr_enum.next)
				rescue StopIteration
					break
				end
			end
			new_arr
		end
		return enum unless block
		enum.each(&block)
	end
	
	def compact
		ArrayParallel.new(@_arr.compact)
	end
	
	def compact!
		return self if @_arr.compact
		nil
	end
	
	def concat(*args)
		args.map! do |arg|
			arg.is_a?(ArrayParallel) ? arg.__get_array__ : arg
		end
		@_arr.concat(*args)
		self
	end
	
	def count(*args, &block)
		@_arr.count(*args, &block)
	end
	
	#допустим я хочу сделать так:
	#ArrayParallel.[]('a', 'b', 'c').cycle(100).to_a
	#эта конструкция должна вернуть Array или ArrayParallel?
	#если ArrayParallel, то как это реализовать?
	'''def cycle(n, &block)
		enum = Enumerator.new do |yielder|
			#new_arr = ArrayParallel.new
			#_arr_enum = @_arr.cycle(n)
			#loop do
			#	begin
			#		new_arr << (yielder.yield _arr_enum.next)
			#	rescue StopIteration
			#		break
			#	end
			#end
			#new_arr
			@_arr.cycle(n) do |elem|
				yielder.yield elem
			end
			#ArrayParallel.new(result)
		end
		return enum unless block
		enum.each(&block)
	end'''
	
	#реализовал часть методов, на все не хватило сил
end

#ТЕСТЫ

#def arrayDebugPrint(arr)
#	puts arr.class.to_s + " " + arr.to_s
#end

puts "-- Тесты создания и операций над массивами --"
puts ArrayParallel.new(['a', 'b', 'c']).slice(0..1).inspect
puts ArrayParallel.[]('a', 'b', 'c')[0..1].inspect

x = ArrayParallel.[]('a', 'b', 'c')
x[1..2] = ['Q', 'W']
puts x.inspect
puts x.to_s

puts "-- Тесты any? --"
puts ArrayParallel.[]('1', '2', '3').all?(Numeric)
puts ArrayParallel.[](1, 2i, 3.14).all?(Numeric)
puts ArrayParallel.[]('111', '222', '33').all? { |word| word.length >= 3 }
puts ArrayParallel.[]('111', '222').all? { |word| word.length >= 3 }

#ary = ArrayParallel.[](0, 4, 7, 10, 12)
#puts ary.bsearch {|x| x >=   4 }
#puts ary.bsearch {|x| x >=   6 }

puts "-- Тесты map и select --"

x = ArrayParallel.new((1..5).to_a)
puts x.map.inspect
puts (x.map.each.with_index {|x, i| x.to_s + ",i=" + i.to_s}).inspect
puts (x.map {|x| x.to_s + "!" }).inspect
puts (x.select {|x| x < 4 }).inspect
puts x.inspect
puts (x.map! {|x| x.to_s + "!" }).inspect
puts x.inspect

puts "-- Тесты корректности многопоточности в any? --"
require 'benchmark'
puts "Создание массива..."
x = ArrayParallel.new((1..10000000).to_a)
puts "Тест первый запущен, должен работать долго..."
x[9999999] = -1
time = Benchmark.measure do
	puts (x.any? { |i| i == -1 })
end
puts "Тест первый завершен за #{time.real} секунд"
puts "----------------------------------------------"
puts "Тест второй запущен, должен завершаться быстро..."
x[1] = -1 #первый поток быстро найдет нужный элемент
time = Benchmark.measure do
	puts (x.any? { |i| i == -1 })
end
puts "Тест второй завершен за #{time.real} секунд"
puts "----------------------------------------------"
puts "Тест третий запущен, должен завершаться быстро..."
x[1] = 0 #второй поток быстро найдет нужный элемент
x[2501000] = -1
time = Benchmark.measure do
	puts (x.any? { |i| i == -1 })
end
puts "Тест третий завершен за #{time.real} секунд"
puts "----------------------------------------------"
puts "Готово"

#x = ArrayParallel.[]('a', 'b', 'c', 'd', 'e')
#x.combination(3) {|x| puts x.to_s}
#p x.combination(3).to_a

#x = ArrayParallel.[]('a', 'b', 'c', 'd', 'e')
#y = ArrayParallel.[]('d', 'e')
#z = Array.[]('1', '2', '3')
#arrayDebugPrint(x.concat(y, z))

#x = ArrayParallel.[]('a', 'b', 'c')
#i = 0
#p x.cycle(100) { |elem| putc elem }

#p ArrayParallel.[]('a', 'b', 'c').cycle(100).to_a

#arrayDebugPrint( ArrayParallel.[]('a', 'b', 'c').each.with_index {|x, i| puts x } )