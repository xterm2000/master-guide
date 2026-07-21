 
sudo systemctl stop ollama
sudo systemctl disable ollama
sudo rm /etc/systemd/system/ollama.service

# Remove ollama libraries from your lib directory (either `/usr/local/lib`, `/usr/lib`, or `/lib`):
sudo rm -r $(which ollama | tr 'bin' 'lib')

# Remove the ollama binary from your bin directory (either `/usr/local/bin`, `/usr/bin`, or `/bin`):
sudo rm $(which ollama)

# Remove the downloaded models and Ollama service user and group:
sudo userdel ollama
sudo groupdel ollama
sudo rm -r /usr/share/ollama
 