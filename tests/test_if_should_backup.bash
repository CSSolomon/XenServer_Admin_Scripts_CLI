function log(){
    echo $@ 1>&2
}

        function get_value_by_key(){
            # Helper function that gets other-config values based on key.
            # Required arguments: Positional:
            #+  vm-uuid
            #+  key name
            # Optional arguments: None
            xe vm-param-get                             \
                uuid="${1}"                             \
                param-name=other-config                 \
                param-key="XenCenter.CustomFields.${2}" ;
            return $?
        } # /get_value_by_key



        function get_vm_backup_parameters(){
            # Prints on stdout the vm backup parameters in a way that bash can parse.
            #+ The output of this function can then be sourced directly into the script.
            # Required arguments: Positional:
            #   uuid of vm
            # Optional arguments: None
            local l_vm_uuid=${1};
            local l_params_are_set="";
            local l_param_value="";
            # Below duplicates code from get_value_by_key because it silently discards errors.
            l_params_are_set=$(xe vm-param-get uuid=${l_vm_uuid}               \
                param-name=other-config                                        \
                param-key=XenCenter.CustomFields.has_backup_params 2>/dev/null);
            local l_status="$?"
            if [ -z "${l_params_are_set}" ] ; then
                l_params_are_set="0";
            fi
            if [ "0"  -ne "${l_status}" -o "1" -ne "${l_params_are_set}" ] ;then
                set_vm_backup_parameters ${l_vm_uuid} && \
                    get_vm_backup_parameters ${l_vm_uuid};
                return $? ;
            fi # /if something went wrong while getting the parameters.

            for i in \
                "backup_type"           \
                "xva_backup_freq"       \
                "template_backup_freq"  \
                "backup_live"           \
                "xva_backlog"           \
                "template_backlog"      \
                "template_sr"           ; do
                l_param_value=$(get_value_by_key ${l_vm_uuid} ${i})

                if [ -z "${l_param_value}" ] ;then 
                    if [ "template_sr" != "${i}" ]; then
                        log ERROR "VM ${l_vm_uuid} does not have parameter ${i} set."
                        eval "l_param_value=\${default_${i}}";
                    fi #/ if the unset value is not template_sr then set to default and warn
                      
                elif  [ 'default' == "${l_param_value}" ]; then
                    log INFO "VM ${l_vm_uuid} parameter ${i} set to 'default'"
                    eval "l_param_value=\${default_${i}}";
                fi ; #/ if parameter blank or 'default'

                echo "${i}=${l_param_value}";
            done ; # /for each key.

        } # /function get_vm_backup_parameters
# ========================================= CODE TO TEST AND COPY


        function get_if_should_backup(){
            # Returns 0 if the VM should be backed-up, taking constraints into
            #+ consideration.
            # Required arguments: Maps of:
                # vm_uuid               : valid uuid
                # backup_type           : xva, template, xva-template, never
                # check_for             : xva, template
            # Mutually exclusive arguments: Maps of:
                # xva_backup_freq       : daily, weekly, monthly, never
                # template_backup_freq  : daily, weekly, monthly, never
            # Optional arguments: None
            # Sample call:
            # get_if_should_backup "vm_uuid:${l_vm_uuid}"                         \
            #                      "backup_type:${l_backup_type}"                 \
            #                      "check_for:template"                           \
            #                      "template_backup_freq:${template_backup_freq}";

            # The following one-liner replaces the command-line arguments
            #+ passed to the function with an expression that, when evaluated
            #+ locally, produces the desired assignments.
            for i in $(for i in $*; do echo "l_${i}" | sed -e "s/:/=/"; done); do
                eval local $i;
            done
            
            local l_backup_freq="";
            local backedup_today="0";

            if [[ "${l_check_for}"  == template ]] ; then
                l_backup_freq="${l_template_backup_freq}"
                # Check if there is a template from today already.
                backedup_today=$(xe template-list                                   \
                    "other-config:XenCenter.CustomFields.template-of=${l_vm_uuid}"  \
                    "other-config:XenCenter.CustomFields.created-on=${full_date}"   | \
                    wc -l );
            elif [[ "${l_check_for}"  == xva ]] ; then
                l_backup_freq="${l_xva_backup_freq}"
                # Check if there is a file from today already.
                backedup_today=$(find "${xva_storage_path}" \
                    -name "*${l_vm_uuid}*" 2>/dev/null      | \
                    grep -e "${full_date}"                  | \
                    wc -l);
            else
                log ERROR "Unknown backup type: ${l_check_for}"
                return 1;
            fi

            if [ "never" == "${l_backup_type}" ] ;then
                log INFO "VM ${l_vm_uuid} has backup frequency set to 'never'"
                return 1;
            fi # /if backup_type is never.
            
            if [ "0" -ne "${backedup_today}" ]; then
                return 1;
            fi # /if there is a backup from today.

            #if [[ "${l_check_for}" != ** ]] ; then
            if ! ( echo "${l_backup_type}" | grep -q -e "${l_check_for}" ) ; then
                log INFO "VM ${l_vm_uuid} does not require ${l_check_for} type backups."
                return 1;
            fi # /if backup_type is asymphonous with type being checked for.

          

            # TODO Backup type may be set with frequency set to never. 
            #+ There is no check for this as of yet because it is something that
            #+ should not occur and is thus treated as not occuring.

            if [ "daily" == "${l_backup_freq}" ] ;then
                return 0;
                # Check if VM schedule is set to daily. If so, a backup should be taken.
            fi

            get_vm_has_backups      \
                "${l_vm_uuid}"      \
                "${l_check_for}" ; 
            if [ "0" -ne "$?" ] ;then
                # Check if there are any backups of the VM as of yet. If not
                #+ one should be taken out of turn.
                log INFO "VM with uuid ${l_vm_uuid} has no backups. Create one.";
                return 0;
            fi
            
            # If weekly / monthly, see if it's the appropriate time.
            if [ "weekly" == "${l_backup_freq}" ] ; then
                if [ "1" -eq "${weekly_backup_today}" ] ; then
                    return 0;
                else
                    return 1;
                fi
            elif [ "monthly" == "${l_backup_freq}" ]; then
                if [ "1" -eq "${monthly_backup_today}" ] ; then
                    return 0;
                else
                    return 1;
                fi
            else 
                # Something went wrong. Log.
                log WARNING "Unknown ${l_check_for}  backup frequency for VM ${l_vm_uuid}: ${l_backup_freq}."
                return 1;
            fi
            log ERROR "Unexpectate case occured in ${l_vm_uuid}"
            return 1;
        } # function get_if_should_backup
