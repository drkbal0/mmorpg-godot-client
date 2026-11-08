# MMORPG Shared Core - Godot Client

Este módulo contiene la lógica compartida que se distribuye entre los clientes de PC y Móvil.

## ⚠️ Reglas de Arquitectura de Red (HTTP)

Para mantener la consistencia en el manejo de sesiones, tokens JWT y telemetría, se han establecido las siguientes reglas obligatorias:

1. **Uso Obligatorio de `APIClient`**: Toda comunicación REST/HTTP hacia el Platform Backend (Go) **DEBE** realizarse exclusivamente a través del singleton `APIClient.gd`.
2. **Prohibición de Nodos `HTTPRequest` Manuales**: No se deben instanciar ni utilizar nodos `HTTPRequest` de forma independiente dentro de los componentes de UI o Manager para llamadas al backend.
3. **Inyección de JWT Automática**: `APIClient` se encarga de inyectar el header `Authorization: Bearer <token>` recuperando el token activo de `AuthManager`.
4. **Manejo de Errores Centralizado**: `APIClient` emite señales globales (`request_failed`, `unauthorized_access`) permitiendo que el sistema reaccione de forma uniforme (ej. redirigir a login tras expirar el token).

### Ejemplo de uso:

```gdscript
var res = await APIClient.get_request("/shelter/inventory")
if res.has("data"):
    print("Éxito: ", res["data"])
else:
    print("Error: ", res["error"])
```
