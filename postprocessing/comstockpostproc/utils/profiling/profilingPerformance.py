# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
import re
import csv
import os
import glob
import logging
import json
from collections import namedtuple, deque

from datetime import datetime
import tarfile


logging.basicConfig(level='INFO')  # Use DEBUG, INFO, or WARNING

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
PROFILING_SUMMARY_DIR = "profiling_summary"

def main(path, selecting_run=None):
    """
    main function:
    - read the log file from tar.gz
    - parse the log file and filter out the useful information.
    - generate log summary based on the cleaned nested log.
    """
    logger.info("Analyzing log files from {}".format(path))
    count = 0
    for logpath, log in __extract_running_log(path):
        informationLines = cleanup_original_log(log)

        #logpath example: ./up00/bldg0000001/out.osw
        if logpath.split("/")[1] not in selecting_run:
            continue

        count += 1
        if count % 10 == 0:
            logger.info(f"Analyzing log path: {logpath}")
            logger.info(f"processed {count} logs")

        if not informationLines:
            logger.info(f">>>>>>> This is Empty >>>>>>  in path: {path}, logpath: {logpath}")
            continue


        # timeDeltaFromCleanedLog = generate_nest_log_from_namedtuple(informationLines)
        timeDeltaFromCleanedLog = _generate_printable_log(informationLines)
        timeDeltaFromCleanedLog['logpath'] = logpath
        generatingReport(timeDeltaFromCleanedLog, path)
    aggregate_csv(path)

def __compute_delta(timestamps):
    """
    helper function: calculate the time usage for an action.
    """
    try:
        format = "%H:%M:%S.%f"
        return int(abs((datetime.strptime(timestamps[0], format) - datetime.strptime(timestamps[1], format)).total_seconds()))
    except ValueError: #the osw.out's start_time and end_time mixed with two kinds of formats.
        end_format = "%Y-%m-%dT%H:%M:%S.%f"
        start_format = "%Y%m%dT%H%M%SZ"
        return int(abs((datetime.strptime(timestamps[0], start_format) - datetime.strptime(timestamps[1], start_format)).total_seconds()))

def __extract_running_log(tar_path):
    """
    helper function: find the singularity_output.log from tar.gz.
    """
    with tarfile.open(tar_path, 'r') as t:
        for member in t.getmembers():
            if "SR" in member.name: #in this approach, I will only extract the log from the
                #highest level (which is not the sizing run)
                continue
            if "out.osw" in member.name:
                logfile = t.extractfile(member)
                try:
                    outoswjson = json.loads(logfile.read())
                    yield (member.name, outoswjson)
                except Exception as e:
                    logging.info(f"the log file {member.name} is not a valid json file due to {e}")
                    continue

def _generate_printable_log(nestedLog: dict) -> dict:
    """
    Generate a printable log from a nested log dictionary.

    Args:
        nestedLog (dict): A nested log dictionary containing performance information.

    Returns:
        dict: A printable log dictionary.

    """
    res = {}
    _id = nestedLog.get("id")
    building_id, upgrade_id = _id.split("up")[0], "up"+_id.split("up")[1]
    temp =[
    {
        'upgrade_id': upgrade_id,
        'building_id': building_id,
        'type': 'total',
        'measure_dir': 'total',
        'workflow_substate': 'total',
        'name': 'total',
        'measure_state': 'total',
        'time': nestedLog.get("total_time")
    }]

    for tuple in nestedLog.get("step_info"):

        if len(tuple) == 2:
            detail = tuple[0].split(".")
            if "result.total" in tuple[0]:

                temp.append({
                    'upgrade_id': upgrade_id,
                    'building_id': building_id,
                    'type': 'step_detail',
                    'measure_dir': detail[1],
                    'workflow_substate': 'step',
                    'name': "total",
                    'measure_state': 'total',
                    'time': tuple[1]
                })
                continue

            measure_total = tuple[1]

            for existed in temp:
                if existed['upgrade_id'] == upgrade_id \
                    and existed['measure_dir'] == detail[1] \
                    and existed['measure_state'] == 'total' \
                    and existed['type'] == 'step_detail':
                    existed['time'] -= measure_total
            temp.append({
            'upgrade_id': upgrade_id,
            'building_id': building_id,
            'type': 'measure_detail',
            'measure_dir': detail[1],
            'workflow_substate': 'measure',
            'name': detail[-1],
            'measure_state': 'total',
            'time': measure_total
            })

        else:
            measure_detail = tuple.pop(0).split(".")
            measure_total = tuple.pop()
            for existed in temp:
                if existed['upgrade_id'] == upgrade_id \
                    and existed['measure_dir'] == detail[1] \
                    and existed['measure_state'] == 'total' \
                    and existed['type'] == 'step_detail':
                    existed['time'] -= measure_total

            measure_datum = {
                'upgrade_id': upgrade_id,
                'building_id': building_id,
                'type': 'measure_detail',
                'measure_dir': measure_detail[1],
                'workflow_substate': 'measure',
                'name': detail[-1],
                'measure_state': 'runtime',
                'time': measure_total
            }

            sizing_total = 0
            for sr in tuple:
                sr_detail = sr[0].split(".")
                sr_total = sr[1]
                sizing_total += sr_total
                temp.append({
                    'upgrade_id': upgrade_id,
                    'building_id': building_id,
                    'type': 'measure_detail',
                    'measure_dir': sr_detail[1],
                    'workflow_substate': 'sizing',
                    'name': sr_detail[-1],
                    'measure_state': 'runtime',
                    'time': sr_total
                })
            measure_datum['time'] = measure_total - sizing_total
            temp.append(measure_datum)
    res['log_detail'] = temp

    return res

def cleanup_original_log(originalLog: dict) -> dict:
    """
    read the original log and filter out the useful information.
    the input dict should be the result from out.osw
    """
    res = {}
    # print(originalLog.get("completed_status"))
    if originalLog.get("completed_status") != "Success":
        logger.debug(f"the log is not successfully completed: {originalLog.get('completed_status')}")
        return res

    if not originalLog.get("steps"):
        logger.debug("the log is empty")
        return res
    if not originalLog.get("started_at") or not originalLog.get("completed_at"):
        logger.debug("the log is empty")
        return res
    if not originalLog.get("id"):
        logging.debug("the log is lack of id information")
        return res

    res["total_time"] = __compute_delta([originalLog.get("started_at") , originalLog.get("completed_at")])
    res['step_info'] = __cleanup_step_logs(originalLog.get("steps", []))
    res['id'] = originalLog['id']
    return res

def __cleanup_step_logs(log: list) -> list:
    """
    helper function: filter out the useful information from the log.
    """
    step_info = []
    keyWord = {"Calling", "runtime", "Started simulation", "Finished simulation"}
    for idx, item in enumerate(log):
        #use the 'measure_dir_name' as the key to identify the step
        for k, v in __flatten_dict(item, parent_key=f"step.{item.get('measure_dir_name')}.{idx}").items():

            if any(char in k for char in {"result.started_at", "result.completed_at"}):
                step_info.append((k, idx, v))

            if "step_info" in k:
                for idx, logline in enumerate(v):
                    if any(char in logline for char in keyWord):
                        step_info.append((k, idx, logline.split("\n")[0]))
    res = __build_namedtuple_from_log(step_info)

    return res

def __build_namedtuple_from_log(step_log: list) -> list:
    """
    Builds a namedtuple from the given step log.

    Args:
        step_log (list): A list of tuples representing the step log.

    Returns:
        list: A list containing the built namedtuple objects.
    """
    queue = deque([])

    measure = []
    step_time = {}
    for key, _, logline in step_log:

        if "step" in key and "result.completed_at" in key:
            step_index = ".".join(key.split(".")[:3])
            step_time[step_index] = logline

        if "step" in key and "result.started_at" in key:
            step_index = ".".join(key.split(".")[:3])
            queue.append([step_index + ".result.total", __compute_delta([logline, step_time[step_index]])])

        if "Calling" in logline:
            measure.append(key + "." + logline.split(" ")[1])

        if "runtime" in logline:
            runtime = float(logline.split(" ")[-2])
            # queue.append(MEASURE_END(timestamp=queue.pop().timestamp, measure=measure[0], runtime=runtime))
            measure.append(runtime)
            queue.append(measure)
            measure = []

        if "Started simulation" in logline:
            log = logline.split(" ")
            sr_name = log[-3].split("/")[-1]
            sr_time = log[-1]
            measure.append([key+".sizing."+sr_name, sr_time])

        if "Finished simulation" in logline:
            log = logline.split(" ")
            sr_name = log[-3].split("/")[-1]
            sr_time = log[-1]
            for tuple in measure:
                if sr_name in tuple[0]:
                    starttime = tuple[1]
                    delta = __compute_delta([starttime, sr_time])
                    tuple[1] = delta
    return queue


def __flatten_dict(d, parent_key='', sep='.'):
    items = []
    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.extend((__flatten_dict(v, new_key, sep=sep).items()))
        else:
            items.append((new_key, v))
    return dict(items)

def generatingReport(nestedLog: dict, path: str):
    """
    After nested log is generated, read the nested log and generate csv file.
    """
    logpath = nestedLog.get('logpath')
    upgrade_id = logpath.split("/")[1]
    building_id = logpath.split('/')[2].replace('bldg', '')[-4:]

    field_names = nestedLog.get("log_detail")[0].keys()

    summaryPath = os.path.join(os.path.dirname(path), "profiling_summary")
    if not os.path.exists(summaryPath):
        os.makedirs(summaryPath)

    path = path.replace('.', '_').replace('/', '_').replace('tar.gz', "")
    summaryFullPath = summaryPath + "/" + "reporting_{}.csv".format(path)
    with open(summaryFullPath, mode='a', newline="") as file:
        writer = csv.DictWriter(file, fieldnames=field_names)
        if not file.tell():
            writer.writeheader()

        for log in nestedLog.get("log_detail"):
            writer.writerow(log)

def aggregate_csv(path: str):
    """
    After all the csv are generated, aggregate the csvs from each run.
    """
    summaryPath = os.path.join(os.path.dirname(path), PROFILING_SUMMARY_DIR)
    with open(summaryPath + '/' + 'aggregate_profiling.csv', 'w') as fout:
        wout = csv.writer(fout, delimiter=',')
        interesting_files = glob.glob(summaryPath + "/" + "*tar_gz.csv")
        h = True
        for filename in interesting_files:
            # Open and process file
            logger.info("Aggregating {}".format(filename))
            with open(filename, 'r') as fin:
                if h:
                    h = False
                else:
                    next(fin) # Skip header
                for line in csv.reader(fin):
                    wout.writerow(line)
