# This project includes code from the Avocado-VT project, which is licensed under the GNU General Public License, version 2 or later (GPLv2+). The original code can be found at https://github.com/avocado-framework/avocado-vt.
#
# Modifications made by: Farrah Chen <farrah.chen@intel.com> - Mar. 2026
# Original License: GNU General Public License, version 2 or later (GPLv2+)
# Modified Code License: GNU General Public License, version 2 or later (GPLv2+)

import re
import logging
from datetime import datetime
from six.moves import xrange
from avocado.core import exceptions
from avocado.utils import process

LOG = logging.getLogger("avocado." + __name__)


def _get_kernel_messages(time, level_check=3, session=None):
    """
    Reads kernel messages for all levels up to certain level.
    See details in function `verify_dmesg`

    :param time: timestamp for dmesg --since
    :param level_check: level of severity of issues to be checked
    :param session: guest
    :return: 3-tuple (environ, output, status)
            environ: (guest|host) indicating where the messages
                     have been read from
            output: multi-line string containing all read messages
            status: exit code of read command
    """
    full_dmesg_cmd = "dmesg -T -l %s |grep . --color=never" % ",".join(
        map(str, xrange(0, int(level_check))))
    if time == 0:
        cmd = full_dmesg_cmd
        LOG.warning("Timestamp from /dev/kmsg is overwritten, check full dmesg from boot")
    elif time == "full":
        cmd = full_dmesg_cmd
    else:
        cmd = "dmesg -T -l %s --since '%s' |grep . --color=never" % (",".join(
            map(str, xrange(0, int(level_check)))), time
        )

    if session:
        environ = "guest"
        status, output = session.cmd_status_output(cmd)
    else:
        environ = "host"
        out = process.run(
            cmd, timeout=30, ignore_status=True, verbose=False, shell=True
        )
        status = out.exit_status
        output = out.stdout_text
    return environ, output, status


def _intersec(list1, list2):
    """
    Returns a new list containing the elements that are present
    in both without any specific order.

    :param list1: some list
    :param list2: some list
    :return: unordered list, the intersection of the input lists
    """

    return [x for x in list1 if x in list2]


def _remove_dmesg_matches(messages="", expected_dmesg=""):
    """
    Removes all messages that match certain regular expressions

    :param messages: single (possibly multi-line) string
    :param expected_dmesg: single string comma separated list of
                           regular expressions whose matches are to be
                           ignored during verification, e.g. "'x.*', 'y.*'"
    :return: The subset of `messages` that doesn't match
    """
    if not expected_dmesg:
        return messages

    __messages = messages.split("\n")
    if "" in __messages:
        __messages.remove("")

    __expected = expected_dmesg.strip('" ').split(",")
    expected_messages = [x.strip(" '") for x in __expected]
    filtered_messages = __messages

    for expected_regex in expected_messages:
        not_matching = [x for x in __messages if not re.findall(expected_regex, x)]
        filtered_messages = _intersec(filtered_messages, not_matching)
    return filtered_messages


def _log_full_dmesg(dmesg_log_file, environ, output):
    """
    Logs all dmesg messages

    :param dmesg_log_file: if given, messages will be written into this file
    :param environ: (guest|host)
    :param output: messages
    :return: string for test log
    """
    err = "Found unexpected failures in %s dmesg log." % environ
    d_log = "dmesg log:\n%s" % output
    if dmesg_log_file:
        with open(dmesg_log_file, "w+") as log_f:
            log_f.write(d_log)
        err += " Please check %s dmesg log %s." % (environ, dmesg_log_file)
    else:
        err += " Please check %s dmesg log in debug log." % environ
        LOG.debug(d_log)
    return err


def dmesg_time(session=None):
    """
    The timestamp in dmesg is not aligned with the timestamp from date in OS.
    To check the dmesg during the specified time period by "dmesg --since",
    input a marker into /dev/kmsg to show and record the initial timestamp.
    :param session: session object to guest
    :return: string for formatted timestamp from dmesg marker
    """
    kmsg_cmd = "echo 'Input from /dev/kmsg: to show the timestamp' > /dev/kmsg"
    show_time_cmd = "dmesg -T | tail -n 1|grep timestamp"
    if session:
        formatted_time = "full"
        return formatted_time
    else:
        marker_status = process.system(kmsg_cmd, shell=True)
        time_status, time_output = process.getstatusoutput(show_time_cmd, shell=True)
    if marker_status:
        LOG.error("/dev/kmsg is not available, failed to capture timestamp, please check your Kconfig and dmesg, continue test!")
        formatted_time = "unknown"
        return formatted_time
    if time_status:
        LOG.error("Timestamp from /dev/kmsg is overwritten, check full dmesg from boot")
        formatted_time = 0
        return formatted_time
    raw_timestamp = re.search(r"\[(\w+ \w+  ?\d+ \d{2}:\d{2}:\d{2} \d{4})\]", time_output).group(1)
    raw_format = "%a %b %d %H:%M:%S %Y"
    out_format = "%Y-%m-%d %H:%M:%S"
    timestamp = datetime.strptime(raw_timestamp, raw_format)
    formatted_time = timestamp.strftime(out_format)
    return formatted_time


def verify_dmesg(
    time,
    dmesg_log_file=None,
    ignore_result=False,
    level_check=3,
    session=None,
    expected_dmesg="",
):
    """
    Find host/guest call trace in dmesg log.

    :param time: timestamp for dmesg --since
    :param dmesg_log_file: The file used to save host dmesg. If None, will save
                           guest/host dmesg to logging.debug.
    :param ignore_result: True or False, whether to fail test case on issues
    :param level_check: level of severity of issues to be checked
                        1 - emerg
                        2 - emerg,alert
                        3 - emerg,alert,crit
                        4 - emerg,alert,crit,err
                        5 - emerg,alert,crit,err,warn
    :param session: session object to guest
    :param expected_dmesg: single string comma separated list of
                           regular expressions whose matches are to be
                           ignored during verification, e.g. "'x.*', 'y.*'"
    :param return: if ignore_result=True, return True if no errors/crash
                   observed, False otherwise.
    :param raise: if ignore_result=False, raise TestFail exception on
                  observing errors/crash
    """
    if time == "unknown":
        LOG.error("/dev/kmsg is not available, failed to capture timestamp, please check your Kconfig and dmesg, continue test!")
        return True
    environ, output, status = _get_kernel_messages(time, level_check, session)
    if status == 0:
        unexpected_messages = _remove_dmesg_matches(output, expected_dmesg)
        err = _log_full_dmesg(dmesg_log_file, environ, output)
        if not ignore_result and unexpected_messages:
            raise exceptions.TestFail(err)
        if unexpected_messages:
            LOG.debug(err)
        return False
    return True
