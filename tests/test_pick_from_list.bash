#!/bin/bash
    function pick_from_list(){
        # Reads input from stdin and matches it against the list of its args.
        #+ returns only when successfully matched.
        # Required arguments: list of valid inputs. 
        #   For numbers the arguments allowed are:
        #       <integer>       (any int)
        #       <posinteger>    (int > 0)
        #       <posorzero>     (int >=0)
        while true; do # Infinite loop, return when valid input
            unset REPLY;
            if [ "<posinteger>" ==  "${1}" ]; then
                echo -n "Please give a positive integer ( >0): " 1>&2
                read;
                if [ -z "${REPLY}" ]; then
                    continue;
                fi # / if reply empty.
                if [[ "${REPLY}" == [^0-9] ]] ;then
                    echo "Invalid option. Please only use numeric arguments." 1>&2
                    continue;
                fi # / if reply not a number
                if [ "0" -ge "${REPLY}" ]; then
                    echo "Invalid input, please try again."  1>&2
                    continue;
                fi # / if value within range.
                echo ${REPLY};
                return 0;
            elif [ "<posorzero>" ==  "${1}" ]; then
                echo -n "Please give a positive integer ( >=0): " 1>&2
                read;
                if [ -z "${REPLY}" ]; then
                    continue;
                fi # / if reply empty.
                if [[ "${REPLY}" == [^0-9] ]] ;then
                    # Reply was empty string or not a number.                     
                    echo "Invalid option. Please only use numeric arguments." 1>&2
                    continue;
                fi # / if reply not a number
                if [ "0" -gt "${REPLY}" ]; then
                    echo "Invalid input, please try again."  1>&2
                    continue;
                fi # / if value within range.
                echo ${REPLY}
                return $?
            elif [ '<integer>' ==  "${1}" ]; then
                echo -n "Please give an integer: " 1>&2
                read;
                if [ -z "${REPLY}" ]; then
                    continue;
                fi # / if reply empty.
                # TODO does not handle negatives. (Not necessary so far)
                if [[ "${REPLY}" == [^0-9] ]] ;then
                    # Reply was empty string or not a number.                     
                    echo "Invalid option. Please only use numeric arguments." 1>&2
                    continue;
                fi # / if reply not a number
                echo ${REPLY}
                return $?
            else
                count=1;
                for i in ${@}; do
                    echo "$((count++)). ${i}" 1>&2;
                done ; # /for i in all args.
                echo -n "Please select the *list number* of one of the " 1>&2
                echo -n "above options: " 1>&2
                read;
                if [ -z "${REPLY}" ]; then
                    echo "";
                    continue;
                fi # / if reply empty.
                if [[ "${REPLY}" == [^0-9] ]] ;then
                    # Reply was empty string or not a number.                     
                    echo "Invalid option. Please only use numeric arguments." 1>&2
                    continue;
                elif [ "0" -lt "${REPLY}" -a "${REPLY}" -le "$#" ]; then
                    # FIXME this part is "dangerous". What it does is replace the
                    #+ value of Reply with an actual number and pass that to eval 
                    #+ to echo the corresponding cmdline argument.
                    eval echo \${$REPLY};
                    return 0;
                else
                    echo "Value out-of-range. Please try again." 1>&2
                    continue;
                fi # /if selection numeric and within range.
            fi  # /if numbers or list
        done
    } ; # / function pick_from_list



echo "Backup type"
l_backup_type="$(pick_from_list template xva xva-template never)";
echo $l_backup_type
echo ""

echo "XVA backup frequency"
l_xva_backup_freq="$(pick_from_list daily weekly monthly never)";
echo $l_xva_backup_freq
echo ""

echo "Template backup frequency";
l_template_backup_freq="$(pick_from_list daily weekly monthly never)";
echo $l_template_backup_freq
echo ""

echo "Backup live"
l_backup_live="$(pick_from_list true false)";
echo $l_backup_live
echo ""

echo "XVA backlog"
l_xva_backlog="$(pick_from_list \<posorzero\>)";
echo $l_xva_backlog
echo ""

echo "Template backlog"
l_template_backlog="$(pick_from_list <posorzero>)";
echo $l_template_backlog
echo ""
