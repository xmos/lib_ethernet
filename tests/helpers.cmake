macro(get_json_list json_dict json_key out_list)
    string(JSON json_array GET ${json_dict} ${json_key})

    set(out_list "")
    if(json_array MATCHES "^\\[.*\\]$")
        string(JSON array_len LENGTH ${json_array})
        math(EXPR last_idx "${array_len} - 1")
        foreach(idx RANGE ${last_idx})
            string(JSON elem GET ${json_array} ${idx})
            list(APPEND ${out_list} ${elem})
        endforeach()
    else()
        list(APPEND ${out_list} ${json_array}) # It's not an array but a single element
    endif()
endmacro()

