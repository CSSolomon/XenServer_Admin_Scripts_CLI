function log(){
    echo $@ 1>&2
}

    default_backup_type="${BACKUP_TYPE:-xva-template}"; # USER_MODIFIABLE_OPTION
    default_xva_backup_freq="${XVA_BACKUP_FREQ:-weekly}"; # USER_MODIFIABLE_OPTION
    default_template_backup_freq="${TEMPLATE_BACKUP_FREQ:-weekly}"; # USER_MODIFIABLE_OPTION
    default_backup_live="${BACKUP_LIVE:-1}"; # USER_MODIFIABLE_OPTION
    default_xva_backlog="${XVA_BACKLOG:-1}"; # USER_MODIFIABLE_OPTION
    default_template_backlog="${TEMPLATE_BACKLOG:-1}"; # USER_MODIFIABLE_OPTION
    default_template_sr="${TEMPLATE_SR:-local}"; # USER_MODIFIABLE_OPTION


    function get_all_vm_uuids(){
        # Returns the uuids of all the vms on the server 
        # Required arguments: None
        # Optional arguments: None
        # TODO a list of optional arguments to indicate vm characteristics
        # to get the list of.
        xe vm-list --minimal is-control-domain=false | \
            sed -e "s/,/ /g";
        return $?
    } # function get_all_vm_uuids

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

# This is the part being developed.


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



# Test area.
for i in $(get_all_vm_uuids); do
    echo $i:
    echo '-----------------------------' 
    get_vm_backup_parameters $i
    echo -e "=====================================\n\n"
done
