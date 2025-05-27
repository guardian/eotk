#!/bin/sh

MAKE=make
keyserver="keyserver.ubuntu.com"

CustomiseVars() {
    install_dir="$opt_dir/$tool.d" 
    tool_tarball=$(basename "$tool_url")
    if [ "$tool" != "tor" ]; then 
        tool_sig=$(basename "$tool_sig_url")
    fi
    tool_dir=$(basename "$tool_tarball" .tar.gz)
}

SetupTorSpecificBuild() {
    local sha_sum_file_name="${tool_tarball}.sha256sum"
    local sha_sum_sig_file_name="${sha_sum_file_name}.asc"
    local sha_sum_url="${tool_url}.sha256sum"
    local sha_sum_sig_url="${sha_sum_url}.asc"

    if [ ! -f "$tool_tarball" ]; then
        curl -L -f -o "$tool_tarball" "$tool_url"
        if [ $? -ne 0 ]; then echo "curl failed for tarball $tool_tarball"; exit 1; fi
    fi

    if [ ! -f "$sha_sum_file_name" ]; then
        curl -L -f -o "$sha_sum_file_name" "$sha_sum_url"
        if [ $? -ne 0 ]; then echo "curl failed for sha256sum file $sha_sum_file_name"; exit 1; fi
    fi

    if [ ! -f "$sha_sum_sig_file_name" ]; then
        curl -L -f -o "$sha_sum_sig_file_name" "$sha_sum_sig_url"
        if [ $? -ne 0 ]; then echo "curl failed for sha256sum signature $sha_sum_sig_file_name"; exit 1; fi
    fi

    gpg --keyserver "hkps://$keyserver" --recv-keys $tool_signing_keys || { echo "gpg recv-keys failed for $tool_signing_keys"; exit 1; }

    gpg --verify "$sha_sum_sig_file_name" "$sha_sum_file_name" || { echo "gpg verify failed for checksum file $sha_sum_file_name"; exit 1; }

    grep " $tool_tarball\$" "$sha_sum_file_name" > "${sha_sum_file_name}.for_verify" 
    if [ ! -s "${sha_sum_file_name}.for_verify" ]; then
        echo "ERROR: Could not find checksum for '$tool_tarball' in '$sha_sum_file_name'"
        echo "Contents of '$sha_sum_file_name':"
        cat "$sha_sum_file_name"
        rm -f "${sha_sum_file_name}.for_verify"
        exit 1
    fi

    sha256sum --status -c "${sha_sum_file_name}.for_verify"
    local checksum_rc=$?
    rm -f "${sha_sum_file_name}.for_verify"

    if [ $checksum_rc -ne 0 ]; then
        echo "SHA256 CHECKSUM MISMATCH for $tool_tarball!"
        echo "Expected sum from $sha_sum_file_name:"
        grep " $tool_tarball\$" "$sha_sum_file_name"
        echo "Calculated sum:"
        sha256sum "$tool_tarball"
        exit 1
    fi

    test -d "$tool_dir" || { echo "Extracting $tool_tarball..."; tar zxf "$tool_tarball" || { echo "tar extract failed for $tool_tarball"; exit 1; } }
    rm -f "$sha_sum_file_name" "$sha_sum_sig_file_name"

    cd "$tool_dir" || { echo "cd to $tool_dir failed"; exit 1; }
}

SetupStandardBuild() {
    if [ ! -f "$tool_tarball" ]; then
        curl -L -f -o "$tool_tarball" "$tool_url"
        if [ $? -ne 0 ]; then echo "curl failed for tarball $tool_tarball"; exit 1; fi
    fi

    if [ ! -f "$tool_sig" ]; then
        curl -L -f -o "$tool_sig" "$tool_sig_url"
        if [ $? -ne 0 ]; then echo "curl failed for signature $tool_sig"; exit 1; fi
    fi

    gpg --keyserver "hkps://$keyserver" --recv-keys $tool_signing_keys || { echo "gpg recv-keys failed for $tool_signing_keys"; exit 1; }

    gpg --verify "$tool_sig" "$tool_tarball" || { echo "gpg verify failed for $tool"; exit 1; }

    test -d "$tool_dir" || { echo "Extracting $tool_tarball..."; tar zxf "$tool_tarball" || { echo "tar extract failed for $tool_tarball"; exit 1; } }
    cd "$tool_dir" || { echo "cd to $tool_dir failed"; exit 1; }
}

SetupForBuild() {
    if [ "$tool" = "tor" ]; then
        SetupTorSpecificBuild
    else
        SetupStandardBuild
    fi
}

BuildAndCleanup() {
    $MAKE || { echo "$MAKE failed for $tool"; exit 1; }
    $MAKE install || { echo "$MAKE install failed for $tool"; exit 1; }
    cd "$opt_dir" || { echo "cd to $opt_dir failed after build"; exit 1; } 
    
    for x in $tool_link_paths ; do
        ln -sf "$install_dir/$x" || { echo "symlink creation failed for $install_dir/$x"; exit 1; }
    done
    
    if [ -n "$tool_sig" ] && [ "$tool" != "tor" ]; then 
        rm -f "$tool_sig"
    fi
    rm -f "$tool_tarball" 
    rm -rf "$tool_dir"  
}

SetupOpenRestyVars() {
    tool="openresty"
    tool_version="1.15.8.3"
    tool_signing_keys="25451EB088460026195BD62CB550E09EA0E98066"
    tool_url="https://openresty.org/download/$tool-$tool_version.tar.gz"
    tool_sig_url="https://openresty.org/download/$tool-$tool_version.tar.gz.asc"
    tool_link_paths="nginx/sbin/nginx"
}

ConfigureOpenResty() {
    or_mods="https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git"
    or_opts="--with-http_sub_module"
    or_mod_list=""

    for mod_url in $or_mods ; do
        mod_dir=$(basename "$mod_url" .git)
        if [ -d "$mod_dir" ] ; then
            ( cd "$mod_dir" && exec git pull ) || { echo "git pull failed for $mod_dir"; exit 1; }
        else
            git clone "$mod_url" || { echo "git clone failed for $mod_url"; exit 1; }
        fi
        or_mod_list="$or_mod_list --add-module=$mod_dir"
    done

    ./configure --prefix="$install_dir" $or_opts $or_mod_list "$@" || { echo "OpenResty configure failed"; exit 1; }
}

SetupTorVars() {
    tool="tor"
    tool_version="0.4.8.9"
    local alex_faeroy_key="514102454D0A87DB0767A1EBBE6A0531C18A9179"
    local david_goulet_key="B74417EDDF22AC9F9E90F49142E86A2A11F48D36"
    local nick_mathewson_key="2133BC600AB133E1D826D173FE43009C4607B1FB"
    tool_signing_keys="$alex_faeroy_key $david_goulet_key $nick_mathewson_key"
    tool_url="https://dist.torproject.org/$tool-$tool_version.tar.gz"
    tool_link_paths="bin/$tool"
}

ConfigureTor() {
    ./configure --prefix="$install_dir" "$@" || { echo "Tor configure failed"; exit 1; }
}