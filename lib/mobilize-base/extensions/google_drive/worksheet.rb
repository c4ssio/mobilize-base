module GoogleDrive
  class Worksheet
    def to_tsv
      sheet = self
      rows = sheet.rows
      header = rows.first
      return nil unless header and header.first.to_s.length>0
      #look for blank cols to indicate end of row
      row_last_i = (header.index("") || header.length)-1
      rows.map{|r| r[0..row_last_i]}.map{|r| r.join("\t")}.join("\n")
    end
    def add_headers(headers)
      headers.each_with_index do |h,h_i|
        self[1,h_i+1] = h
      end
      self.save
    end
    def delete_sheet1
      sheet = self
      #delete sheet1
      sheet1 = sheet.spreadsheet.worksheet_by_title("Sheet1")
      if sheet1
        sheet1.delete
        return true
      end
    end
    def add_or_update_rows(upd_rows)
      sheet = self
      curr_rows = sheet.to_tsv.tsv_to_hash_array
      headers = curr_rows.first.keys
      curr_rows = [] if curr_rows.length==1 and curr_rows.first['name'].nil?
      curr_row_names = curr_rows.map{|r| r['name']}
      upd_rows.each_with_index do |row,urow_i|
        crow_i = curr_row_names.index(row['name'])
        if crow_i.nil?
          curr_row_names << row['name']
          crow_i = curr_row_names.length-1
        end
        row.each do |col_n,col_v|
          col_v_i = headers.index(col_n)
          sheet[crow_i+2,col_v_i+1] = col_v
        end
      end
      sheet.save
    end

    def merge(merge_sheet)
      #write the top left of sheet
      #with the contents of merge_sheet
      sheet = self
      curr_rows = sheet.num_rows
      curr_cols = sheet.num_cols
      merge_rows = merge_sheet.num_rows
      merge_cols = merge_sheet.num_cols
      #make sure sheet is at least as big as necessary
      if merge_rows > curr_rows
        sheet.max_rows = merge_rows
        sheet.save
      end
      if merge_cols > curr_cols
        sheet.max_cols = merge_cols
        sheet.save
      end
      batch_start = 0
      batch_length = 80
      merge_sheet.rows.each_with_index do |row,row_i|
        row.each_with_index do |val,col_i|
          sheet[row_i+1,col_i+1] = val
        end
        if row_i > batch_start + batch_length
          sheet.save
          batch_start += (batch_length+1)
        end
      end
    end

    def write(tsv)
      sheet = self
      tsvrows = tsv.split("\n")
      #no rows, no write
      return true if tsvrows.length==0
      headers = tsvrows.first.split("\t")
      batch_start = 0
      batch_length = 80
      rows_written = 0
      curr_rows = sheet.num_rows
      curr_cols = sheet.num_cols
      #make sure sheet is at least as big as necessary
      if tsvrows.length != curr_rows
        sheet.max_rows = tsvrows.length
        sheet.save
      end
      if headers.length != curr_cols
        sheet.max_cols = headers.length
        sheet.save
      end
      #write to sheet in batches of batch_length
      while batch_start < tsvrows.length
        batch_end = batch_start + batch_length
        tsvrows[batch_start..batch_end].each_with_index do |row,row_i|
          rowcols = row.split("\t")
          rowcols.each_with_index do |col_v,col_i|
            sheet[row_i+batch_start+1,col_i+1]= %{#{col_v}}
          end
        end
        sheet.save
        batch_start += (batch_length + 1)
        rows_written+=batch_length
        if batch_start>tsvrows.length+1
         break
        end
      end
      true
    end
    def check_and_fix(tsv)
      sheet = self
      sheet.reload
      #loading remote data for checksum
      rem_tsv = sheet.to_tsv
      rem_table = rem_tsv.split("\n").map{|r| r.split("\t").map{|v| v.googlesafe}}
      loc_table = tsv.split("\n").map{|r| r.split("\t").map{|v| v.googlesafe}}
      re_col_vs = []
      errcnt = 0
      #checking cells
      loc_table.each_with_index do |loc_row,row_i|
        loc_row.each_with_index do |loc_v,col_i|
          rem_row = rem_table[row_i]
          if rem_row.nil?
            errcnt+=1
            "No Row #{row_i} for Write Dst".oputs
            break
          else
            rem_v = rem_table[row_i][col_i]
            if loc_v != rem_v
              if ['true','false'].include?(loc_v.downcase)
                #google sheet upcases true and false. ignore
              elsif loc_v.starts_with?('rp') and rem_v.starts_with?('Rp')
                # some other math bs
                sheet[row_i+1,col_i+1] = %{'#{loc_v}}
                re_col_vs << {'row_i'=>row_i+1,'col_i'=>col_i+1,'col_v'=>%{'#{loc_v}}}
              elsif (loc_v.to_s.count('e')==1 or loc_v.to_s.count('e')==0) and
                loc_v.to_s.sub('e','').to_i.to_s==loc_v.to_s.sub('e','').gsub(/\A0+/,"") #trim leading zeroes
                #this is a string in scentific notation, or a numerical string with a leading zero
                #GDocs handles this poorly, need to rewrite write_dst cells by hand with a leading apostrophe for text
                sheet[row_i+1,col_i+1] = %{'#{loc_v}}
                re_col_vs << {'row_i'=>row_i+1,'col_i'=>col_i+1,'col_v'=>%{'#{loc_v}}}
              elsif loc_v.class==Float or loc_v.class==Fixnum
                if (loc_v - rem_v.to_f).abs>0.0001
                  "row #{row_i.to_s} col #{col_i.to_s}: Local=>#{loc_v.to_s} , Remote=>#{rem_v.to_s}".oputs
                  errcnt+=1
                end
              elsif rem_v.class==Float or rem_v.class==Fixnum
                if (rem_v - loc_v.to_f).abs>0.0001
                  "row #{row_i.to_s} col #{col_i.to_s}: Local=>#{loc_v.to_s} , Remote=>#{rem_v.to_s}".oputs
                  errcnt+=1
                end
              elsif loc_v.to_s.is_time?
                rem_time = begin
                             Time.parse(rem_v.to_s)
                           rescue
                             nil
                           end
                if rem_time.nil? || ((loc_v - rem_time).abs>1)
                  "row #{row_i.to_s} col #{col_i.to_s}: Local=>#{loc_v} , Remote=>#{rem_v}".oputs
                  errcnt+=1
                end
              else
                #"loc_v=>#{loc_v.to_s},rem_v=>#{rem_v.to_s}".oputs
                if loc_v.force_encoding("UTF-8") != rem_v.force_encoding("UTF-8")
                #make sure it's not an ecoding issue
                  "row #{row_i.to_s} col #{col_i.to_s}: Local=>#{loc_v} , Remote=>#{rem_v}".oputs
                  errcnt+=1
                end
              end
            end
          end
        end
      end
      if errcnt==0
        if re_col_vs.length>0
          sheet.save
          "rewrote:#{re_col_vs.to_s}".oputs
        else
          true
        end
      else
        raise "#{errcnt} errors found in checksum"
      end
    end
  end
end