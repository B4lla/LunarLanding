"""Fixed observation scaling for the SAC landing policy."""
from stable_baselines3.common.torch_layers import BaseFeaturesExtractor
import torch


class LandingFeatures(BaseFeaturesExtractor):
    """Put positions, velocities and attitude on comparable input scales."""

    def __init__(self, observation_space):
        super().__init__(observation_space, features_dim=15)
        self.register_buffer("scales", torch.tensor([
            5.0, 25.0, 5.0, 2.0, 5.0, 2.0,
            1.0, 0.1, 0.1, 0.1, 0.2, 0.2, 0.2, 1.0, 1.0,
        ]))

    def forward(self, observations):
        return observations / self.scales
