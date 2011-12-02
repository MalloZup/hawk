#======================================================================
#                        HA Web Konsole (Hawk)
# --------------------------------------------------------------------
#            A web-based GUI for managing and monitoring the
#          Pacemaker High-Availability cluster resource manager
#
# Copyright (c) 2009-2011 Novell Inc., Tim Serong <tserong@novell.com>
#                        All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it would be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# Further, this software is distributed without any warranty that it is
# free of the rightful claim of any third person regarding infringement
# or the like.  Any license provided herein, whether implied or
# otherwise, applies only to this software file.  Patent licenses, if
# any, provided herein do not apply to combinations of this program with
# other software, or any other product whatsoever.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write the Free Software Foundation,
# Inc., 59 Temple Place - Suite 330, Boston MA 02111-1307, USA.
#
#======================================================================

# Random utilities
module Util

  # Derived from Ruby 1.8's and 1.9's lib/open3.rb.  Returns
  # [stdin, stdout, stderr, thread].  thread.value.exitstatus
  # has the exit value of the child, but if you're calling it
  # in non-block form, you need to close stdin, out and err
  # else the process won't be complete when you try to get the
  # exit status.
  def popen3(*cmd)
    pw = IO::pipe   # pipe[0] for read, pipe[1] for write
    pr = IO::pipe
    pe = IO::pipe

    pid = fork{
      # child
      pw[1].close
      STDIN.reopen(pw[0])
      pw[0].close

      pr[0].close
      STDOUT.reopen(pr[1])
      pr[1].close

      pe[0].close
      STDERR.reopen(pe[1])
      pe[1].close

      exec(*cmd)
    }
    wait_thr = Process.detach(pid)

    pw[0].close
    pr[1].close
    pe[1].close
    pi = [pw[1], pr[0], pe[0], wait_thr]
    pw[1].sync = true
    if defined? yield
      begin
        return yield(*pi)
      ensure
        pi.each{|p| p.close if p.respond_to?(:closed) && !p.closed?}
        wait_thr.join
      end
    end
    pi
  end
  module_function :popen3

  # Like popen3, but via /usr/sbin/hawk_invoke
  def run_as(user, *cmd)
    # crm shell always wants to open/generate help index, so we
    # let it use a group-writable subdirectory of our tmp directory
    # so unprivileged users can actually invoke crm without warnings
    ENV['HOME'] = File.join(RAILS_ROOT, 'tmp', 'home')
    pi = popen3('/usr/sbin/hawk_invoke', user, *cmd)
    if defined? yield
      begin
        return yield(*pi)
      ensure
        pi.each{|p| p.close if p.respond_to?(:closed) && !p.closed?}
      end
    end
    pi
  end
  module_function :run_as

  # Like %x[...], but without risk of shell injection.  Returns STDOUT
  # as a string.  STDERR is ignored. $?.exitstatus is set appropriately.
  # May block indefinitely if the command executed is expecting something
  # on STDIN (untested)
  def safe_x(*cmd)
    pr = IO::pipe   # pipe[0] for read, pipe[1] for write
    pe = IO::pipe
    pid = fork{
      # child
      fork{
        # grandchild
        pr[0].close
        STDOUT.reopen(pr[1])
        pr[1].close
        pe[0].close
        STDERR.reopen(pe[1])
        pe[1].close
        exec(*cmd)
      }
      Process.wait
      exit!($?.exitstatus)
    }
    Process.waitpid(pid)
    pr[1].close
    pe[1].close
    out = pr[0].read()
    pr[0].close
    out
  end
  module_function :safe_x

  # Check if a child process is active by pidfile, but also cleanup stale
  # pidfile if child has gone away unexpectedly.
  def child_active(pidfile)
    active = false
    if File.exists?(pidfile)
      pid = File.new(pidfile).read.to_i
      if pid > 0
        begin
          active = Process.getpgid(pid) == Process.getpgid(0)
        rescue Errno::ESRCH
          # no such process (but nothing to do; active is already false)
        end
      end
      File.unlink(pidfile) unless active
    end
    active
  end
  module_function :child_active

  # Gives back a string, boolean if value is "true" or "false", or nil
  # if initial value was nil (or boolean false) and there's no default
  # TODO(should): be nice to get integers auto-converted too
  def unstring(v, default = nil)
    v ||= default
    ['true', 'false'].include?(v.class == String ? v.downcase : v) ? v.downcase == 'true' : v
  end
  module_function :unstring

  # Does the same job bas crm_get_msec() from lib/common/utils.c
  def crm_get_msec(str)
    m = str.strip.match(/^([0-9]+)(.*)$/)
    return -1 unless m
    msec = m[1].to_i
    case m[2]
    when "ms", "msec"
      msec
    when "us", "usec"
      msec / 1000
    when "s", "sec", ""
      msec * 1000
    when "m", "min"
      msec * 60 * 1000
    when "h", "hr"
      msec * 60 * 60 * 1000
    else
      -1
    end
  end
  module_function :crm_get_msec

  # Check if some feature is supported by the installed version of pacemaker.
  # TODO(should): expand to include other checks (e.g. pcmk installed).
  def has_feature?(feature)
    case feature
    when :crm_history
      %x[echo quit | /usr/sbin/crm history 2>&1]
      $?.exitstatus == 0
    when :rsc_ticket
      %x[/usr/sbin/crm configure rsc_ticket 2>&1].starts_with?("usage")
    when :rsc_template
      %x[/usr/sbin/crm configure rsc_template 2>&1].starts_with?("usage")
    else
      false
    end
  end
  module_function :has_feature?
end
