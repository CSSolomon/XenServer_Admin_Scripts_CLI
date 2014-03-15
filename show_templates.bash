
function log(){
    echo $@ 1>&2
}




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

        function get_value_by_key_for_template(){
            # Helper function that gets other-config values based on key.
            # Required arguments: Positional:
            #+  vm-uuid
            #+  key name
            # Optional arguments: None
            xe template-param-get                             \
                uuid="${1}"                             \
                param-name=other-config                 \
                param-key="XenCenter.CustomFields.${2}" ;
            return $?
        } # /get_value_by_key



for i in $(get_all_vm_uuids); do
    echo "VM: $i"
    echo "Preserve templates #: $(xe vm-param-get uuid=${i} param-name=other-config param-key=XenCenter.CustomFields.template_backlog)"
    echo "========================================="
    
    all_vm_templates=( $(										    \
        xe template-list --minimal                                  \
            other-config:XenCenter.CustomFields.template-of="${i}"  | \
        sed -e 's/,/\n/g'											));
        
    for template in ${all_vm_templates[@]}; do
        creation_date=$(get_value_by_key_for_template ${template} created-on)
        echo "${creation_date:-19000101} ${template}"; 
    done | sort
    echo "-----------------------------------------"
    echo ""
done
