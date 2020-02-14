import requests

account = {"id": "1", "first_name": "Alex", "last_name": "Smith"}
header = {'auth-token' : 'ee7fbd80-a9ac-4dcf-8e43-7c98a969c33c'}

r = requests.post(url = "http://172.19.0.2:8080/http", json = account, headers = header)
