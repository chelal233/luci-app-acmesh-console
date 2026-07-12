acmesh_json_escape() {
	printf '%s' "${1-}" | awk '
		{
			if (NR > 1) {
				printf "\\n";
			}
			for (i = 1; i <= length($0); i++) {
				c = substr($0, i, 1);
				if (c == "\\") {
					printf "\\\\";
				} else if (c == "\"") {
					printf "\\\"";
				} else if (c == "\t") {
					printf "\\t";
				} else if (c == "\r") {
					printf "\\r";
				} else {
					printf "%s", c;
				}
			}
		}
	'
}
