#!/usr/bin/python

import argparse, requests, json, pprint, csv
from types import *
#from os import path

katello = {}
katello['user'] = "user"
katello['pass'] = "xxx"
katello['uri'] = "https://<KATELLO|SATELLITE HOSTNAME>/katello/api/v2"
csv_content = {'katello_id': '', 'name': '', 'uuid': '', 'content_view_id': '', 'environment': {'name': '', 'label': ''}, 'errata_counts': {'security': '', 'bugfix': '', 'enhancement': '', 'total': ''}, 'errata_list': [ {'errata_id': '', 'title': '', 'issued': '', 'updated': '', 'severity': '', 'reboot_suggested': '', 'type': '', 'cves': [ {'cve_id': '', 'href': ''} ], 'packages': [ '' ]} ] }
csv_head = ['katello_id','system_name','content_view_id','environment_label','errata_counts_security','errata_counts_bugfix','errata_counts_enhancement','errata_counts_total','errata_id','errata_title','errata_issued','errata_updated','errata_severity','reboot_suggested','errata_type','errata_cves','packages','system_uuid']


def arg_parser():
	global args
	opt_parser = argparse.ArgumentParser(description='Exports list of erratas for systems in specifed organization into CSV file.')
	opt_parser.add_argument('--org', default='<ORGANIZATION>', required=True, help='Katello organization label to list systems in that organization. Default: "wincor-nixdorf"')
	#opt_parser.add_argument('--org-id', default='3', help='Katello organization ID to list systems in that organization.')
	opt_parser.add_argument('--csv-file', help='CSV output file. Default: "./errata_list.csv"')
	args = opt_parser.parse_args()

# get json from katello api
def get_data(api_uri):
	data = json.loads( requests.get( katello['uri'] + api_uri, auth=(katello['user'], katello['pass']), verify=False ).content )
	return data['results']

# get list of organizations
def get_org_list():
	global org_list
	org_list = {}
	data = get_data('/organizations')
	for org in data:
		org_list[str(org['id'])] = org['label']
		org_list[org['label']] = str(org['id'])
	
# get list of content views
def get_cv_list():
	global cv_list
	cv_list = {}
	data = get_data('/content_views')
	for cv in data:
		cv_list[cv['id']] = cv['label']

# extract information defined by reference from source structure (lists, dicts, list of dicts, etc...)
def dict_subset(source_dict, ref_dict):
	if type(source_dict) is dict:
		tmp_dict = {}
		for key in ref_dict:
			if type(ref_dict[key]) is dict:
				tmp_dict[key] = dict_subset(source_dict[key], ref_dict[key])
			elif type(ref_dict[key]) is list:
				tmp_dict[key] = dict_subset(source_dict[key], ref_dict[key])
			else:
				tmp_dict[key] = source_dict[key]
	
	elif type(ref_dict) is list:
		tmp_dict = []
		for i,val in enumerate(source_dict):
			if type(ref_dict[0]) is dict:
				tmp_dict.append( dict_subset(source_dict[i], ref_dict[0]) )
			elif type(ref_dict[0]) is list:
				tmp_dict.append( dict_subset(source_dict[i], ref_dict[0]) )
			else:
				tmp_dict.append( source_dict[i] )
	
	else:
		tmp_dict = source_dict
	
	return tmp_dict


def main():
	global katello
	
	arg_parser()
	get_cv_list()
	get_org_list()

	org_id = org_list[args.org]
	
	# get list of system in specified organization
	#data = json.loads( requests.get( katello['test_uri'], verify=False ).content )
	systems_list = get_data('/organizations/' + org_id + '/systems?per_page=100000')

	#data = json.loads( requests.get( katello['uri'] + '/systems/' + 'd8fd7008-3e5d-4de0-93b0-93d71e4fac46' + '/errata', auth=(katello['user'], katello['pass']), verify=False ).content )
	#systems_list[0]['errata_list'] = data['results']
	#sys = dict_subset(systems_list[0], csv_content)

	# write array to csv file
	output_file = args.csv_file
	open(output_file, 'w').close()
	with open(output_file, 'a') as csv_file:
		writer = csv.writer(csv_file, delimiter=';', quoting=csv.QUOTE_ALL)
		writer.writerow(csv_head)
	
		# go through all systems
		for i,sys in enumerate(systems_list):

			# add errata information to the global systems_list
			systems_list[i]['errata_list'] = get_data( '/systems/' + sys['uuid'] + '/errata')
			print i, '\t ' + str(sys['katello_id']) + '\t ' + sys['uuid'] + '\t ' + sys['name']
			print i, ' ' + sys['uuid'] + ' ' + sys['name']

			# extract only needed information from global systems_list defined by csv_content
			#for system in systems_list:
			dict_subset(sys, csv_content)
		
			# create array of values which can be written to csv file
			csv_array = []
			for errata in sys['errata_list']:
				errata_cves = ''
				for errata_cve in errata['cves']:
					errata_cves = errata_cves + ' | ' + errata_cve['cve_id']
				for pkg in errata['packages']:
					csv_array.append( [ sys['katello_id'], sys['name'], cv_list[sys['content_view_id']], sys['environment']['label'], sys['errata_counts']['security'], sys['errata_counts']['bugfix'], sys['errata_counts']['enhancement'], sys['errata_counts']['total'], errata['errata_id'], errata['title'], errata['issued'], errata['updated'], errata['severity'], errata['reboot_suggested'], errata['type'], errata_cves, pkg, sys['uuid'] ] )

			writer.writerows(csv_array)
	

if __name__ == "__main__":
	main()
