class Gmail
  class Message
    def initialize(gmail, mailbox, uid)
      @gmail = gmail
      @mailbox = mailbox
      @uid = uid
    end

    def inspect
      "<#Message:#{object_id} mailbox=#{@mailbox.name}#{' uid='+@uid.to_s if @uid}#{' message_id='+@message_id.to_s if @message_id}>"
    end

    # Auto IMAP info
    def uid
      @uid ||= @gmail.imap.uid_search(['HEADER', 'Message-ID', message_id])[0]
    end

    # IMAP Operations
    def flag(flg)
      @gmail.in_mailbox(@mailbox) do
        @gmail.imap.uid_store(uid, "+FLAGS", [flg])
      end ? true : false
    end

    def unflag(flg)
      @gmail.in_mailbox(@mailbox) do
        @gmail.imap.uid_store(uid, "-FLAGS", [flg])
      end ? true : false
    end

    # Gmail Operations
    def mark(flag)
      case flag
      when :read
        flag(:Seen)
      when :unread
        unflag(:Seen)
      when :deleted
        flag(:Deleted)
      when :spam
        move_to('[Gmail]/Spam')
      end ? true : false
    end

    def delete!
      @mailbox.messages.delete(uid)
      flag(:Deleted)
    end

    def label(name)
      @gmail.in_mailbox(@mailbox) do
        begin
          @gmail.imap.uid_copy(uid, name)
        rescue Net::IMAP::NoResponseError
          raise Gmail::NoLabel, "No label `#{name}' exists!"
        end
      end
    end

    def label!(name)
      @gmail.in_mailbox(@mailbox) do
        begin
          @gmail.imap.uid_copy(uid, name)
        rescue Net::IMAP::NoResponseError
          # need to create the label first
          @gmail.create_label(name)
          retry
        end
      end
    end

    # We're not sure of any 'labels' except the 'mailbox' we're in at the moment.
    # Research whether we can find flags that tell which other labels this email is a part of.
    # def remove_label(name)
    # end

    def move_to(name)
      label(name) && delete!
    end

    def archive!
      move_to('[Gmail]/All Mail')
    end

    # Parsed MIME message object
    def message
      return @message if @message

      require 'mail'

      part = "RFC822"
      if @gmail.peek
        part = 'BODY[]'
      end

      _body = fetch_data.attr[part]
      @message = Mail.new(_body)      
    end

    def fetch_data
      return @fetch_data if @fetch_data

      request = "(X-GM-MSGID RFC822.SIZE FLAGS RFC822)"    
      if @gmail.peek
        request = "(X-GM-MSGID RFC822.SIZE FLAGS BODY.PEEK[])"
      end

      @fetch_data = @gmail.in_mailbox(@mailbox) { @gmail.imap.uid_fetch(uid, request)[0] }
    end

    def gm_msgid
      fetch_data.attr["X-GM-MSGID"]
    end

    def rfc822_size
      fetch_data.attr["RFC822.SIZE"]
    end

    def flags
      fetch_data.attr["FLAGS"]
    end

    def respond_to?(name)
      super || message.respond_to?(name)
    end

    private
    

    # Delegate all other methods to the Mail message
    def method_missing(*args, &block)
      if block_given?
        message.send(*args, &block)
      else
        message.send(*args)
      end
    end
  end
end
