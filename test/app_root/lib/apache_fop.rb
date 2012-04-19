module ApacheFop
  # Returns a closed Tempfile which contains the pdf
  def self.generate_pdf(xsl_fo, options = {})
    temp_files = Hash[[:fo, :pdf, :errout].map{|fn| [fn, Tempfile.new(fn.to_s)]}]
    begin
      temp_files[:fo].write(xsl_fo)
      temp_files.each{|k,t| t.close}

      # FIXME Should use FOP as an http service instead, it would be faster.
      # Can I somehow forward its response directly to the client?
      system(
        "fop" +
        " -fo \"#{temp_files[:fo].path}\" " +
        " -pdf \"#{temp_files[:pdf].path}\" " +
        " >\"#{temp_files[:errout].path}\" 2>&1"
      )
      fop_info = File.read(temp_files[:errout].path)
      if fop_info =~ /SEVERE: Exception/
        raise "Apache FOP raised an internal exception: #{fop_info}"
      end

      unless File.size?(temp_files[:pdf].path)
        raise "Apache FOP failed to generate a PDF: #{fop_info}"
      end

      if options[:auto_print]
        unless options[:from_url]
          raise "The auto_print option requires the from_url option"
        end
        append_auto_print(temp_files[:pdf].path, options[:from_url])
      end

      return temp_files[:pdf]
    ensure
      [:fo, :errout].each{|sym| temp_files[sym].close!}
    end
  end

  private

  def self.append_auto_print(path, from_url)
    # FIXME: All the parsing code below assumes single-char line endings
    # Also assuming that the PDF doesn't already have secondary sections
    catalog_obj = nil
    catalog_obj_num = nil
    catalog_obj_gen = nil
    file_trailer = nil
    orig_xref_pos = nil
    orig_size = nil

    File.open(path) do |fh|
      # Extract the file trailer
      fh.seek(-1024, IO::SEEK_END)
      file_trailer = fh.read()
      file_trailer.sub!(/.+^trailer/m, "trailer")
      raise "Could not find PDF trailer section" unless file_trailer =~ /trailer/

      if file_trailer =~ /^startxref\s*^(\d+)/m
        orig_xref_pos = $1.to_i
      else
        raise "Could not find PDF xref position"
      end

      if file_trailer =~ /Size (\d+)/
        orig_size = $1.to_i
      else
        raise "Could not find PDF obj count"
      end

      if file_trailer =~ /\/Root (\d+) (\d+) R/
        catalog_obj_num = $1.to_i
        catalog_obj_gen = $2.to_i
      else
        raise "Could not find PDF catalog obj num"
      end

      fh.seek(orig_xref_pos)
      fh.gets # Skip the "xref" line
      cur_num = 0
      while fh.gets
        if $_ =~ /^(\d+) \d+\s*$/
          # Start of an xref section at the given number
          cur_num = $1.to_i
        elsif $_ =~ /^(\d+) (\d+) ([nf])\s*$/
          offset, gen, xtype = $1.to_i, $2.to_i, $3
          if xtype == "n" && cur_num == catalog_obj_num && gen = catalog_obj_gen
            fh.seek(offset)
            catalog_obj = ""
            while fh.gets
              catalog_obj += $_
              break if catalog_obj =~ /\bendobj/
            end
            if catalog_obj !~ /\bendobj/
              raise "No proper end found to PDF catalog section"
            end
            catalog_obj.sub!("endobj", "")
            break
          end
          cur_num += 1
        elsif $_ =~ /^trailer/
          raise "Couldn't find root xref in PDF"
        else
          raise "Invalid xref line in PDF: '#{$_}'"
        end
      end
      raise "Could not find PDF catalog section" unless catalog_obj
    end

    # Append the updated catalog section and new action objects
    File.open(path, "a") do |fh|
      new_catalog_pos = fh.pos
      fh.puts catalog_obj.sub(">>", "  /OpenAction #{orig_size} 0 R\n>>")
      fh.puts "endobj"

      print_action_pos = fh.pos
      fh.puts "#{orig_size} 0 obj"
      fh.puts "<<"
      fh.puts "  /Type /Action"
      fh.puts "  /S /Named"
      fh.puts "  /N /Print"
      fh.puts "  /Next #{(orig_size+1).to_s} 0 R"
      fh.puts ">>"
      fh.puts "endobj"

      uri_action_pos = fh.pos
      fh.puts "#{orig_size+1} 0 obj"
      fh.puts "<<"
      fh.puts "  /Type /Action"
      fh.puts "  /S /URI"
      fh.puts "  /URI (#{from_url})"
      fh.puts ">>"
      fh.puts "endobj"

      xref_pos = fh.pos
      fh.puts "xref"
      fh.puts "#{catalog_obj_num} 1"
      fh.puts "%010u %05u n " % [new_catalog_pos, 0]
      fh.puts "#{orig_size} 2"
      fh.puts "%010u %05u n " % [print_action_pos, 0]
      fh.puts "%010u %05u n " % [uri_action_pos, 0]

      fh.puts file_trailer.sub(
        ">>", "/Prev #{orig_xref_pos}\n>>"
      ).sub(
        /Size \d+/, "Size #{orig_size.to_i+2}" # 2 new objs
      ).sub(
        /startxref\s*^\d+/m, "startxref\n#{xref_pos}"
      )
    end
  end
end
