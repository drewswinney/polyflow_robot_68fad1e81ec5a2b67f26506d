################################################################################
# Services (patched)
################################################################################

systemd.services.polyflow-setup = {
  description = "Clone/update Polyflow robot repo and colcon build";
  wantedBy = [ "multi-user.target" ];
  after = [ "network-online.target" "time-sync.target" ];
  wants = [ "network-online.target" "time-sync.target" ];

  path = with pkgs; [ git colcon python3 ros-pkgs.rosPackages.humble.ros2cli ];

  serviceConfig = {
    Type = "oneshot";
    User = user;
    Group = "users";
    WorkingDirectory = homeDir;
    StateDirectory = "polyflow";
    StandardOutput = "journal";
    StandardError  = "journal";
  };

  script = ''
    set -eo pipefail

    export HOME=${homeDir}

    if [ -d "${homeDir}/${repoName}" ]; then
      echo "[setup] Repo exists; pulling latest…"
      cd "${homeDir}/${repoName}"
      git pull --ff-only
    else
      echo "[setup] Cloning repo…"
      git config --global --unset https.proxy || true
      git clone "https://github.com/drewswinney/${repoName}.git" "${homeDir}/${repoName}"
      chown -R ${user}:users "${homeDir}/${repoName}"
    fi

    echo "[setup] Building with colcon…"
    cd "${wsDir}"
    colcon build
    echo "[setup] Done."
  '';
};

systemd.services.polyflow-webrtc = {
  description = "Run Polyflow WebRTC launch with ros2 launch";
  wantedBy = [ "multi-user.target" ];
  after = [ "polyflow-setup.service" "network-online.target" ];
  wants = [ "polyflow-setup.service" "network-online.target" ];

  # Only need the ros2 binary on PATH
  path = [ ros-pkgs.rosPackages.humble.ros2cli ];

  environment = {
    RMW_IMPLEMENTATION = "rmw_cyclonedds_cpp";
    ROS_DOMAIN_ID = "0";
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

  serviceConfig = {
    Restart = "always";
    RestartSec = "3s";
    User = user;
    Group = "users";
    WorkingDirectory = wsDir;
    StateDirectory = "polyflow";
    StandardOutput = "journal";
    StandardError  = "journal";
  };

  script = ''
    # keep -e and -o pipefail, but drop global -u to avoid colcon env hook issues
    set -eo pipefail

    if [ -f "${wsDir}/install/setup.sh" ]; then
      echo "[webrtc] Sourcing colcon overlay…"
      # Temporarily allow unset vars; colcon env scripts set/expect these.
      set +u
      . "${wsDir}/install/setup.sh"
      set -u
    else
      echo "[webrtc] No install/setup.sh found; did build succeed?" >&2
      exit 1
    fi

    echo "[webrtc] Launching…"
    exec ros2 launch webrtc launch/webrtc.launch.py
  '';
};
