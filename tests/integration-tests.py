import requests

url = "https://home.kowi.it/"

def test_home_assistant_route():
    response = requests.get(url)
    assert response.status_code == 200
