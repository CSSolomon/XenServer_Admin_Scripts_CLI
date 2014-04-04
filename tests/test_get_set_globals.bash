globals=(                     \
    "snapshot_to_destroy:"    \
    "vm_to_start:"            \
    "unmount_nfs:1"           \
    "partial_file_to_remove:"); # /globals
globals_file=$(mktemp /tmp/globals.XXXXXXX);




function log(){
    echo $@ 1>&2
}

function set_global(){
    # Set the values of global variables.
    #+ Uses an intermediate file to allow functions to modify and share values,
    #+ something bash does not regularly allow.
    # Required arguments: Mappings:
    #+  key:value pair for global variable.
    # Optional arguments: None
    local l_key_value_pair="${1}";
    local l_current_key_value_pair="";
    local l_key="";
    local l_value="";
    local l_default_value="";
    l_key=$(echo ${l_key_value_pair} | cut -d ":" -f 1);
    l_value=$(echo ${l_key_value_pair} | cut --complement -d ":" -f 1);

    echo "${l_key_value_pair}" | grep -q -e ":"
    if [ "0" -ne "$?" -o -z "${l_key}" ] ; then
        log "set_global not in format <key>:<value>. Instead: ${1}"
        return 1;
    fi # /if format not key:value. 
    
    l_default_value=$(for i in ${globals[@]}; do
            echo ${i};
        done | grep -e "^${l_key}:.*"
    ); # Find if variable is in the default values and get default value.
    if [ -z "${l_default_value}" ] ;then
        log "Attempting to set non-existing global ${l_key}";
        return 1;
    fi

    if [ ! -r "${globals_file}" ]; then
        log "Globals file does not exist or not readable.";
        return 1;
    fi # /if global file not present / not readable.

    l_current_key_value_pair=$(
        grep -e "^${l_key}:.*" "${globals_file}"
    ); #/ get current value in the file.

    if [ -z "${l_current_key_value_pair}" ]; then # if value not yet in file - add.
        # sed does not insert in empty files, therefore this workaround is required.
        if [ "0" -eq "$(cat ${globals_file} | wc --bytes)" ] ; then
            echo "${l_key_value_pair}" >> "${globals_file}"
        else
            sed -i -e "1i${l_key_value_pair}" "${globals_file}";
        fi
    else # else value in file - replace
        sed -i -e "/^${l_key}:.*/c${l_key_value_pair}"  "${globals_file}";
    fi

    return 0;
} # /function set_global


function get_global(){
    # Get the values of global variable based on key.
    #+ Uses an intermediate file to allow functions to modify and share values,
    #+ something bash does not regularly allow.
    # Required arguments: Positional:
    #+  name of global variable.
    # Optional arguments: None
    local l_variable_name="${1}";
    local l_key_value_pair="";
    local l_key="";
    local l_value="";
    local l_default_value="";

    # Check that the variable name is in the list of recognised globals. If
    #+ so, keep it's default value.
    l_default_value=$(for i in ${globals[@]}; do
            echo ${i};
        done | grep -e "^${l_variable_name}:.*"
    ); # Find if variable is in the default values and get default value.

    if [ -z "${l_default_value}" ] ;then
        log "Requested non-existing global ${l_variable_name}";
        return 1;
    fi # /if default value is null.

    # If the value isn't found in the file, call set_global to set it first.
    l_key_value_pair=$( grep -e "${l_variable_name}:.*" ${globals_file} );
    if [ -z "${l_key_value_pair}" ] ;then
        set_global ${l_default_value} &&    \
            {
                l_value=$(get_global ${l_variable_name});
                echo l_value: ${l_value};
            }
        return $?
    fi

    l_key=$(echo ${l_key_value_pair} | cut -d ":" -f 1);
    l_value=$(echo ${l_key_value_pair} | cut --complement -d ":" -f 1);
    echo "${l_value}";
    return 0;
} # /function get_global

get_global snapshot_to_destroy
get_global vm_to_start
get_global unmount_nfs
get_global partial_file_to_remove
get_global partial_file_to_remov

#set_global "partial_file_to_remove:alithia"
#set_global "snapshot_to_destroy:1"
#set_global "vm_to_start:3@@@"
#set_global "unmount_nfs:1111"
#set_global "unmount_nfss:1111"
#
#get_global snapshot_to_destroy
#get_global vm_to_start
#get_global unmount_nfs
#get_global partial_file_to_remove
#
#
#set_global "unmount_nfs:"
#set_global "partial_file_to_remove:psemma"
#set_global "snapshot_to_destroy:10"
#set_global "vm_to_start:xxxx"
#set_global "unmount_nfs:2222"
#set_global "unmount_nfss:1111"
#
#get_global snapshot_to_destroy
#get_global vm_to_start
#get_global unmount_nfs
#get_global partial_file_to_remove
