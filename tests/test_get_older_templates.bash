
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




function test_get_older_templates(){
    l_vm_uuid=${1}
    l_backup_type=template
    preserve_n=$(xe vm-param-get uuid=$l_vm_uuid param-name=other-config param-key=XenCenter.CustomFields.template_backlog)
            if [ "template" == "${l_backup_type}" ] ; then
                # Get all backups that are template-of and ignore the n latest.
                # This is more complex than the xva counterpart because sorting is
			    #+ based on alphanumeric precedence of uuid, not creation date.
				all_vm_templates=( $(													\
                    xe template-list --minimal                                          \
                        other-config:XenCenter.CustomFields.template-of="${l_vm_uuid}"  | \
					sed -e 's/,/\n/g'													));
                log DEBUG "All VM templates for ${l_vm_uuid}: ${all_vm_templates[@]}"

                older_template_uuids=($( for template_uuid in ${all_vm_templates[@]} ; do 
                        creation_date=$(xe template-param-get               \
                                uuid=${template_uuid}                       \
                                param-name=other-config                     \
                                param-key=XenCenter.CustomFields.created-on );
                        # Templates without creation dates are considered ancient
                        echo "${creation_date:-19000101} ${template_uuid}"; 
                    done                            | \
                    sort							| \
                    cut -d " " -f 2                 | \
                    head -n -${preserve_n:-9999}	)); #/ older_template_uuids
                log DEBUG "Older VM templates for ${l_vm_uuid}: ${older_template_uuids[@]}"

                for older_template in ${older_template_uuids[@]} ;do
                    log INFO "removing template with uuid = ${older_template}";
echo                   ' yes yes | xe template-uninstall template-uuid='"${older_template}";
                done; # /for all older templates
         fi       
} #/ test_get_older_templates


for i in $(get_all_vm_uuids); do
    test_get_older_templates $i
done
