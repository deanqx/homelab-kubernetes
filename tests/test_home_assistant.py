import requests

url = "https://home.kowi.it/"

def test_route():
    response = requests.get(url)
    assert response.status_code == 200
