if [ -z "${SAMBA_WRITER_PASSWORD:-}" ]; then
	SAMBA_WRITER_PASSWORD=$(openssl rand -base64 24)
	export SAMBA_WRITER_PASSWORD
fi
