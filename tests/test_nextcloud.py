import requests

url = "https://cloud.kowi.it/"

def test_route():
    response = requests.get(url)
    assert response.status_code == 200
