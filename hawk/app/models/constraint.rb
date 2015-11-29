# Copyright (c) 2009-2015 Tim Serong <tserong@suse.com>
# See COPYING for license.

class Constraint < Record
  class CommandError < StandardError
  end

  validate do |record|
    # to validate a new record:
    # try making the shell form and running verify;commit in a temporary shadow cib in crm
    # if it fails, report errors
    if record.new_record
      cli = record.shell_syntax
      _out, err, rc = Invoker.instance.no_log do |i|
        i.crm_configure ['cib new', cli, 'verify', 'commit'].join("\n")
      end
      err.lines.each do |l|
        record.errors.add :base, l[7..-1] if l.start_with? "ERROR:"
      end if rc != 0
    end
  end

  attribute :object_type, Symbol

  def object_type
    self.class.to_s.downcase
  end

  def mapping
    {
      id: {
        type: "string",
        longdesc: "",
        default: "",
      }
    }
  end

  class << self
    def all
      super(true)
    end

    def find(id, attr = 'id')
      rsc = super(id, attr)
      return rsc if rsc.is_a? Constraint
      raise Cib::RecordNotFound, _("Not a constraint")
    end

    def cib_type_fetch
      :constraints
    end
  end
end
