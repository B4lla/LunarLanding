"""Run and evaluate a saved SAC policy in the Lunar Landing simulator."""
import argparse
from math import hypot
from pathlib import Path

from stable_baselines3 import SAC
from rocket_landing_env.gym_env import RocketLandingEnv

PROJECT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description="Prueba el modelo SAC entrenado.")
    parser.add_argument("--episodios", type=int, default=5)
    start = parser.add_mutually_exclusive_group()
    start.add_argument("--aleatorio", dest="aleatorio", action="store_true", default=True,
                       help="Usa posiciones iniciales aleatorias (predeterminado)")
    start.add_argument("--nominal", dest="aleatorio", action="store_false",
                       help="Empieza centrado a la altura nominal")
    parser.add_argument("--sin-ventana", action="store_true", help="Ejecuta sin mostrar la simulacion")
    parser.add_argument("--modelo", type=Path, default=PROJECT / "python/user_algorithms/sac_rocket.zip",
                        help="Ruta del modelo SAC")
    parser.add_argument("--puerto", type=int, default=55423, help="Puerto local del simulador")
    parser.add_argument("--semilla", type=int, help="Semilla para repetir la misma serie de episodios")
    args = parser.parse_args()
    if args.episodios < 1:
        parser.error("--episodios debe ser mayor que cero")
    if not 1024 <= args.puerto <= 65535:
        parser.error("--puerto debe estar entre 1024 y 65535")
    if args.semilla is not None and not 0 <= args.semilla < 2**31:
        parser.error("--semilla debe estar entre 0 y 2147483647")
    model_path = args.modelo.expanduser().resolve()
    if not model_path.is_file():
        parser.error(f"No se encuentra el modelo: {model_path}. Ejecuta train.bat primero.")
    godot = PROJECT / "Godot_v4.7.2-stable_win64_console.exe"
    if not godot.is_file():
        parser.error(f"No se encuentra Godot: {godot}")
    model = SAC.load(model_path)
    env = RocketLandingEnv(godot_executable=str(godot), project_path=str(PROJECT),
                           headless=args.sin_ventana, random_start=args.aleatorio, port=args.puerto)
    successes = 0
    try:
        for episode in range(1, args.episodios + 1):
            obs, _ = env.reset(seed=args.semilla if episode == 1 else None)
            x, y, z = obs[:3]
            print(f"Intento {episode} | Inicio respecto a la plataforma: "
                  f"X={x:+.2f} m, Y={y:.2f} m, Z={z:+.2f} m", flush=True)
            total = 0.0
            while True:
                action, _ = model.predict(obs, deterministic=True)
                obs, reward, terminated, truncated, info = env.step(action)
                total += reward
                if terminated or truncated:
                    result = info.get("result", "UNKNOWN")
                    landed = result == "SUCCESSFUL LANDING"
                    successes += landed
                    distance = f", distancia al centro: {hypot(obs[0], obs[2]):.2f} m" if landed else ""
                    print(f"Intento {episode}: {result} ({info.get('reason', '')}); "
                          f"tiempo simulado: {info['elapsed_s']:.2f} s, "
                          f"recompensa: {total:.1f}{distance}", flush=True)
                    break
        print(f"Aterrizajes correctos: {successes}/{args.episodios}", flush=True)
    finally:
        env.close()


if __name__ == "__main__":
    main()
