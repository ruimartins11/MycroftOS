#!/usr/bin/env bash

# Copyright 2017 Mycroft AI Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

SOURCE="${BASH_SOURCE[0]}"

script=${0}
script=${script##*/}
cd -P "$( dirname "$SOURCE" )"
DIR="$( pwd )"

function help() {
    echo "${script}:  Mycroft command/service launcher"
    echo "usage: ${script} [COMMAND] [restart] [params]"
    echo
    echo "Services COMMANDs:"
    echo "  all                      runs core services: bus, audio, skills, voice"
    echo "  debug                    runs core services, then starts the CLI"
    echo "  audio                    the audio playback service"
    echo "  bus                      the messagebus service"
    echo "  skills                   the skill service"
    echo "  voice                    voice capture service"
    # echo "  wifi                     wifi setup service"
    echo "  enclosure                mark_1 enclosure service"
    echo
    echo "Tool COMMANDs:"
    echo "  cli                      the Command Line Interface"
    echo "  unittest                 run mycroft-core unit tests (requires pytest)"
    echo "  skillstest               run the skill autotests for all skills (requires pytest)"
    echo
    echo "Util COMMANDs:"
    echo "  audiotest                attempt simple audio validation"
    echo "  audioaccuracytest        more complex audio validation"
    echo "  sdkdoc                   generate sdk documentation"
    echo
    echo "Options:"
    echo "  restart                  (optional) Force the service to restart if running"
    echo
    echo "Examples:"
    echo "  ${script} all"
    echo "  ${script} all restart"
    echo "  ${script} cli"
    echo "  ${script} unittest"

    exit 1
}

_module=""
function name-to-script-path() {
    case ${1} in
        "bus")               _module="mycroft.messagebus.service" ;;
        "skills")            _module="mycroft.skills" ;;
        "audio")             _module="mycroft.audio" ;;
        "voice")             _module="mycroft.client.speech" ;;
        "cli")               _module="mycroft.client.text" ;;
        "audiotest")         _module="mycroft.util.audio_test" ;;
        "audioaccuracytest") _module="mycroft.audio-accuracy-test" ;;
        "enclosure")         _module="mycroft.client.enclosure" ;;

        *)
            echo "Error: Unknown name '${1}'"
            exit 1
    esac
}

first_time=true

# set the right locale / language settings
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

function init-once() {
    sudo fbv -f -d 1 /opt/mycroft/splash/logo.png > /dev/null 2>&1
    if ($first_time) ; then
        echo "Initializing..."
        # Check if Mycroft log folders are present and if not
	# create those logging folders
	if [[ ! -w /var/log/mycroft/ ]] ; then
		# Creating needed folders
		printf "Creating /var/log/mycroft/ directory"
		if [[ ! -d /var/log/mycroft/ ]] ; then
			mkdir /var/log/mycroft/
		fi
	fi
        first_time=false
    fi
}

function launch-process() {
    init-once

    name-to-script-path ${1}

    # Launch process in foreground
    echo "Starting $1"
    python3 -m ${_module} $_params
}

function require-process() {
    # Launch process if not found
    name-to-script-path ${1}
    if ! pgrep -f "python3 -m ${_module}" > /dev/null ; then
        # Start required process
        launch-background ${1}
    fi
}

function launch-background() {
    init-once

    # Check if given module is running and start (or restart if running)
    name-to-script-path ${1}
    if pgrep -f "python3 -m ${_module}" > /dev/null ; then
        if ($_force_restart) ; then
            echo "Restarting: ${1}"
            "${DIR}/stop-mycroft.sh" ${1}
        else
            # Already running, no need to restart
            return
        fi
    else
        echo "Starting background service $1"
    fi

    # Security warning/reminder for the user
    if [[ "${1}" == "bus" ]] ; then
        echo "CAUTION: The Mycroft bus is an open websocket with no built-in security"
        echo "         measures.  You are responsible for protecting the local port"
        echo "         8181 with a firewall as appropriate."
    fi

    # Launch process in background, sending logs to standard location
    python3 -m ${_module} $_params >> /var/log/mycroft/${1}.log 2>&1 &
}

function launch-all() {
    echo "Starting all mycroft-core services"
    launch-background bus
    launch-background skills
    launch-background audio
    launch-background voice
    launch-background enclosure
}

_opt=$1
_force_restart=false
shift
if [[ "${1}" == "restart" ]] || [[ "${_opt}" == "restart" ]] ; then
    _force_restart=true
    if [[ "${_opt}" == "restart" ]] ; then
        # Support "start-mycroft.sh restart all" as well as "start-mycroft.sh all restart"
        _opt=$1
    fi
    shift
fi
_params=$@

case ${_opt} in
    "all")
        launch-all
        ;;

    "bus")
        launch-background ${_opt}
        ;;
    "audio")
        launch-background ${_opt}
        ;;
    "skills")
        launch-background ${_opt}
        ;;
    "voice")
        launch-background ${_opt}
        ;;

    "debug")
        launch-all
        launch-process cli
        ;;

    "cli")
        require-process bus
        require-process skills
        launch-process ${_opt}
        ;;

    # TODO: Restore support for Wifi Setup on a Picroft, etc.
    # "wifi")
    #    launch-background ${_opt}
    #    ;;
    "unittest")
        pytest test/unittests/ --cov=mycroft "$@"
        ;;
    "singleunittest")
        pytest "$@"
        ;;
    "skillstest")
        pytest test/integrationtests/skills/discover_tests.py "$@"
        ;;
    "audiotest")
        launch-process ${_opt}
        ;;
    "audioaccuracytest")
        launch-process ${_opt}
        ;;
    "sdkdoc")
        cd doc
        make ${opt}
        cd ..
        ;;
    "enclosure")
        launch-background ${_opt}
        ;;

    *)
        help
        ;;
esac
