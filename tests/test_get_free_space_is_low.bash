function log(){
    echo $@ 1>&2
}

    function notify_sysadmin(){
        # Sends an e-mail to the system administrator when things have gone horribly wrong.
        #+ Sysadmin should have been checking logs, but that's never guaranteed...
        # Required arguments: Positional:
        #+  Message to be sent
        # Optional arguments: None
        # FIXME IMPLEMENT
        # Empty for now
        return 0;
    } # / notify_sysadmin


    low_space_soft_limit="${LOW_SPACE_SOFT_LIMIT:-$((500 * (1024 ** 3)))}"; # USER_MODIFIABLE_OPTION
    low_space_hard_limit="${LOW_SPACE_HARD_LIMIT:-$((200 * (1024 ** 3)))}"; # USER_MODIFIABLE_OPTION
    nfs_mountpoint="${NFS_MOUNTPOINT:-/mnt}"; # USER_MODIFIABLE_OPTION


    function get_value_in_range(){
        # Issues a warning depending on where free space lies. 
        #+ It could be used to pause operation if hard limit is reached.
        # Required arguments: Positional:
        #+  soft_limit
        #+  hard_limit
        #+  value
        # Optional arguments: Positional:
        #+ previous_state Previous worst case scenario.
        local l_soft_limit=${1};
        local l_hard_limit=${2};
        local l_value=${3};
        local l_previous_worst=${4};
        local l_nocasematch=$(shopt -p nocasematch);
        if [ "${l_hard_limit}" -gt "${l_soft_limit}" ]; then
            log WARNING "Hard limit set higher than soft."
            eval "${l_nocasematch}";
            return 1;
        fi

        if [ "hard" == "${l_previous_worst}" ]; then
            echo "hard";
            eval "${l_nocasematch}";
            return 0;
        fi # /if prefious was hard.

        if [ "${l_value}" -lt "${l_hard_limit}" ];then
            echo "hard";
        # / if hard case.
        elif [ "${l_value}" -lt "${l_soft_limit}" ];then
            echo "soft";
        # /if soft case.
        else 
            if [ "soft" == "${l_previous_worst}" ]; then
                echo "soft";
            else
                echo "fine";
            fi #/if this is fine, previous was soft.
        fi #/if value within ranges.

        eval "${l_nocasematch}";
        return 0;
    } #/get_value_in_range



    function get_sr_free_space(){
        # Calculates the free space on the SR
        # Required arguments: Positional:
        #+  SR UUID
        # Optional arguments: None
        local l_sr_to_probe="${1}";
        
        # The mountpoint is expected to be given as absolute path.
        if { echo "${l_sr_to_probe}" | grep -q -e "/" ; }; then
            available_space=$(df --sync -k -P "${l_sr_to_probe}"    | \
                sed -e 's/[ \t]\+/ /g'                              | \
                cut -d ' ' -f 4                                     | \
                tail -n -1                                          );
            echo $((available_space * 1024 ));
        else
            total_space=$(xe sr-param-get       \
                uuid="${l_sr_to_probe}"         \
                param-name=physical-size        );
            used_space=$(xe sr-param-get        \
                uuid="${l_sr_to_probe}"         \
                param-name=physical-utilisation );
            echo $((total_space - used_space));
        fi # /if sr is uuid or mountpoint.
        return 0;
    } # /get_sr_free_space


    function get_free_space_state(){
        # Issues a warning depending on where free space lies. 
        #+ It could be used to pause operation if hard limit is reached.
        # Required arguments: None
        # Optional arguments: Positional:
        #+  SR uuid 
        local l_sr_to_probe="${1}";
        local l_status="0";

        if [ ! -z "${l_sr_to_probe}" ] ;then
            local l_free_space=$(get_sr_free_space "${l_sr_to_probe}");
            local l_free_space_state=$(get_value_in_range   \
                "${low_space_soft_limit}"                   \
                "${low_space_hard_limit}"                   \
                "${l_free_space}"                     );
        else
            local l_sr_list=( $({ xe sr-list type=nfs --minimal; \
                xe sr-list --minimal type=ext ;} | \
                sed -e "s/,/ /g") ${nfs_mountpoint} );
            for l_sr_to_probe in ${l_sr_list[@]}; do
                # This is necessary because otherwise space released is not recognised.
                xe sr-scan uuid="${l_sr_to_probe}";
                l_free_space=$(get_sr_free_space "${l_sr_to_probe}");
                l_free_space_state=$(get_value_in_range \
                    "${low_space_soft_limit}"           \
                    "${low_space_hard_limit}"           \
                    "${l_free_space}"                   \
                    ${l_free_space_state}               );
                if [ "0" -ne "$?" ] ;then
                    echo "hard";
                    log ERROR "Something went wrong while calculating free space. Consider worst-case scenario."
                    return 1;
                fi
            done # /for all SRs
        fi
        echo "${l_free_space_state}";
        return 0;
    } # / get_free_space_state









# Actual Test

#get_value_in_range 100 50 200
#get_value_in_range 100 50 70
#get_value_in_range 100 50 20
#get_value_in_range 100 50 200 fine
#get_value_in_range 100 50 200 soft
#get_value_in_range 100 50 200 hard
#get_value_in_range 100 50 70 fine
#get_value_in_range 100 50 70 soft
#get_value_in_range 100 50 70 hard
#get_value_in_range 100 50 40 fine
#get_value_in_range 100 50 40 soft
#get_value_in_range 100 50 40 hard

#get_sr_free_space ${1}
#get_sr_free_space /mnt
#get_free_space_state ${1}


