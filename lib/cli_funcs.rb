require 'system_config.rb'
require 'cli_utils.rb'

class CliFuncs
  attr_accessor :basedir, :datadir
  attr_reader :output

  def initialize
    @basedir = String
    @datadir = String
    @output = Array.new
    set_dirs
  end

  def get_env
    ENV['RSYNCONRAILS_CONFIG'] ||= "development"
  end

  def set_dirs
    @basedir = SYSTEM_CONFIG[get_env]["basedir"]
    @datadir = SYSTEM_CONFIG[get_env]["datadir"]
  end
  
  def run_and_capture(*args)
    args.flatten!
    debug = false
    begin
      puts "Args: #{args}" if debug
      stdin, stdout_and_stderr = Open3.popen2e(*args)
      stdout_and_stderr.each do |line|
        @output.push(line)
        p line if debug
      end
    rescue Exception => e
      puts "Tried to run command: #{args[0, args.size]}, received exception: #{e}"
    end
  end
end

class Rsync < CliFuncs
  attr_accessor :flags_run, :cmd_run, :source, :destination
  attr_reader :uptodate, :deleted, :modified, :created, :excluded, :ignored, :basedir, :datadir, :output, :transfer_stats

  def initialize
    super
    @uptodate = Array.new
    @deleted = Array.new
    @modified = Array.new
    @created = Array.new
    @excluded = Array.new
    @ignored = Array.new
    @transfer_stats = Hash.new
    @flags_all = Array.new
    @source = String
    @destination = String
    @output_filter_junk = String
    @output_filter_excluded = String
    @output_filter_warn_err = String
    @output_filter_stats = String
    set_flags_base
    set_output_filters
  end

  def rsync
    run_and_capture(cmd_run)
  end

  def set_output_filters
    set_output_filter_junk
    set_output_filter_excluded
    set_output_filter_warn_err
    set_output_filter_stats
  end

  def output_process
    @output.each do |line|
      if line =~ /#{@output_filter_junk}/ then
        next
      elsif line =~ /#{@output_filter_excluded}/ then
        # Capture excluded stuff here
        next
      elsif line =~ /#{@output_filter_warn_err}/ then
        # Capture warnings / errors here
        next
      elsif line =~ /#{@output_filter_stats}/
        # Set hash of stats
        @transfer_stats[$1] = $2
        @transfer_stats[$3] = $4
        @transfer_stats[$5] = $6
        @transfer_stats[$7] = $8
        @transfer_stats[$9] = $10
        @transfer_stats[$11] = $12
        @transfer_stats[$13] = $14
        @transfer_stats[$15] = $16
        @transfer_stats[$17] = $18
        @transfer_stats[$19] = $20
        @transfer_stats[$21] = $22
        next
      else
        # catch all, this is the main content
        process_itemized(line)
      end
    end
    puts @transfer_stats.inspect
  end

  def process_itemized(line)
    # Break apart the line by spaces (e.g. ".f          9/file9")
    attrs,item = line.split(/\s+/, 2)
    # Break apart itemized attrs on each character 0 = . 1 = f 2 = nil, 3 = nil ...
    attrs_p = attrs.split("")
    # Begin check's for file/directory disposition according to rsync
    # If element 0 contains a '.', it means no update has occurred, but may have attribute changes
    if(attrs_p[0] == ".")
       # This first check ignores directories which have had their timestamp changed
       if(
          attrs_p[1] == "d" and 
          attrs_p[2] == "." and
          attrs_p[3] == "." and
          attrs_p[4] == "t" and
          attrs_p[5] == "." and
          attrs_p[6] == "." and
          attrs_p[7] == "." and
          attrs_p[8] == "." and
          attrs_p[9] == "." and
          attrs_p[10] == "."
       )
          puts "#{line.chomp} IGNORED!"
          @ignored.push(line)
          #return
       # checks if nothing has changed with this item
       elsif(
          attrs_p[1] =~ /f|d|L|D|S/ and 
          attrs_p[2] == nil and
          attrs_p[3] == nil and
          attrs_p[4] == nil and
          attrs_p[5] == nil and
          attrs_p[6] == nil and
          attrs_p[7] == nil and
          attrs_p[8] == nil and
          attrs_p[9] == nil and
          attrs_p[10] == nil
       )
          puts "#{line.chomp} UPTODATE!"
          @uptodate.push(line)
       # something must have changed, like an attribute (e.g. ownership or mode)
       else
          puts "#{line.chomp} MODIFIED OWNERSHIP OR MODE!"
          @modified.push(line) 
       end
    # checks if item is being deleted
    elsif(attrs_p[0] =~ /\*|<|>|c|h/)
      if(
         attrs_p[1] == "d" and 
         attrs_p[2] == "e" and
         attrs_p[3] == "l" and
         attrs_p[4] == "e" and
         attrs_p[5] == "t" and
         attrs_p[6] == "i" and
         attrs_p[7] == "n" and
         attrs_p[8] == "g" and
         attrs_p[9] == nil and
         attrs_p[10] == nil
      )
         puts "#{line.chomp} DELETED!"
         @deleted.push(line) 

      # checks if item is being created (i.e. new file/dir)
      elsif(
        attrs_p[1] =~ /f|d/ and 
        attrs_p[2] == "+" and
        attrs_p[3] == "+" and
        attrs_p[4] == "+" and
        attrs_p[5] == "+" and
        attrs_p[6] == "+" and
        attrs_p[7] == "+" and
        attrs_p[8] == "+" and
        attrs_p[9] == "+" and
        attrs_p[10] == "+"
      )
        puts "#{line.chomp} CREATED!"
        @created.push(line)

      # everthing else is considered a modification
      else
        puts "#{line.chomp} MODIFIED CATCH ALL 1!"
        @modified.push(line) 
      end
    else
      puts "#{line.chomp} MODIFIED CATCH ALL 2!"
      @modified.push(line) 
    end
  end

  def set_output_filter_warn_err
    filter = Array.new

    # These are warnings and errors kicked out by rsync during it's run
    filter.push("WARNING: .* failed verification -- update discarded \(will try again\)\.")
    filter.push("IO error encountered -- skipping file deletion")
    filter.push("file has vanished: .*")
    filter.push("rsync (error|warning): .*")
    filter.push("cannot delete non-empty directory: .*")

    @output_filter_warn_err = filter.join("|")
  end

  def set_output_filter_stats
    filter = Array.new

    # These are for rsync stats which are output after the transfer is complete
    filter.push("(Number of files): (\\d+)")
    filter.push("(Number of files transferred): (\\d+)")
    filter.push("(Total file size): (\\d+) bytes")
    filter.push("(Total transferred file size): (\\d+) bytes")
    filter.push("(Literal data): (\\d+) bytes")
    filter.push("(Matched data): (\\d+) bytes")
    filter.push("(File list size): (\\d+)")
    filter.push("(File list generation time): (.*) seconds")
    filter.push("(File list transfer time): (.*) seconds")
    filter.push("(Total bytes sent): (\\d+)")
    filter.push("(Total bytes received): (\\d+)")

    @output_filter_stats = filter.join("|")
  end

  def set_output_filter_excluded
    filter = Array.new

    # These are files/directories which have been excluded by a pattern we passed to rsync
    filter.push("^(\[generator\]) (excluding|protecting) (directory|file) .* because of pattern .*$")

    @output_filter_excluded = filter.join("|")
  end

  def set_output_filter_junk
    filter = Array.new

    # blank line
    filter.push("^$")
    # ignore line
    filter.push("^sending incremental file list")
    # ignore line
    filter.push("^building file list ...")
    # ignore line
    filter.push("^expand file_list\s\w+")
    # ignore line
    filter.push("^rsync: expand\s\w+")
    # ignore line
    filter.push("^opening connection\s\w+")
    # ignore line - should probably capture this info
    filter.push("^total")
    # ignore line - should probably capture this info
    filter.push("^wrote")
    # ignore line - should probably capture this info
    filter.push("^sent")
    # ignore line
    filter.push("^done")
    # ignore line
    filter.push("^excluding")
    # ignore line
    filter.push("^hiding")
    # ignore line
    filter.push("^delta( |-)transmission (dis|en)abled")
    # ignore line
    filter.push("^deleting in \./")
    # ignore line
    filter.push("^rsync\\[\\d+\\] \\(sender\\) heap statistics:")
    # ignore line
    filter.push("^rsync\\[\\d+\\] \\(server receiver\\) heap statistics:")
    # ignore line
    filter.push("^rsync\\[\\d+\\] \\(server generator\\) heap statistics:")
    # ignore line
    filter.push("^  arena:")
    # ignore line
    filter.push("^  ordblks:")
    # ignore line
    filter.push("^  smblks:")
    # ignore line
    filter.push("^  hblks:")
    # ignore line
    filter.push("^  hblkhd:")
    # ignore line
    filter.push("^  allmem:")
    # ignore line
    filter.push("^  usmblks:")
    # ignore line
    filter.push("^  fsmblks:")
    # ignore line
    filter.push("^  uordblks:")
    # ignore line
    filter.push("^  fordblks:")
    # ignore line
    filter.push("^  keepcost:")

    @output_filter_junk = filter.join("|")
  end

  def cmd_run
    u = CliUtils.new("rsync")
    [u.utility_path, flags_run, @source, @destination].flatten
  end
  
  def flags_run
    @flags_all
  end

  def flag_add(flag)
    @flags_all.push(flag) unless flag == nil
  end

  def flag_delete
    flag_add("--delete")
  end

  def flag_compress
    flag_add("-z")
  end

  def flag_dryrun 
    flag_add("-n")
  end

  def flag_verbose
    flag_add("-vv")
  end

  def flag_archive
    flag_add("-a")
  end

  def flag_itemized
    flag_add("-i")
  end

  def flag_checksum
    flag_add("-c")
  end
  
  def flag_stats
    flag_add("--stats")
  end

  def flag_bwlimit(kbps)
    flag_add("--bwlimit=#{kbps}")
  end

  def flag_rsync_path(path)
    flag_add("--rsync-path=#{path}")
  end

  def set_flags_base
    flag_archive
    flag_verbose
    flag_itemized
    flag_delete
    flag_stats
  end
end
