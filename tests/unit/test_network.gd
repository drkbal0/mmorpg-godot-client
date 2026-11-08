extends "res://addons/gut/test.gd"

## test_network.gd
## Verifies basic NetworkManager and APIClient flow.

func test_api_client_initialization():
	assert_not_null(APIClient, "APIClient should be an Autoload")

func test_network_manager_initialization():
	assert_not_null(NetworkManager, "NetworkManager should be an Autoload")
	assert_eq(NetworkManager.my_session_id, 0, "Initial session ID should be 0")

func test_ticket_request_flow():
	# This would require a mock for APIClient if we want to test in isolation
	# or a running backend for integration testing.
	pass
