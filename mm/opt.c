// SPDX-License-Identifier: GPL-2.0
/*
 * System optimization for SD730G (6GB RAM) devices.
 * Re-applies kernel tuning after vendor init.rc overrides.
 * Uses direct kernel API calls to bypass sysfs/SELinux restrictions.
 * Separate file to avoid cherry-pick conflicts in mm/vmscan.c.
 */
#include <linux/delay.h>
#include <linux/printk.h>
#include <linux/fs.h>
#include <linux/blkdev.h>
#include <linux/genhd.h>
#include <linux/workqueue.h>

extern int vm_swappiness;
extern void cpu_boost_set_params(const char *freq_str, unsigned int boost_ms,
				 unsigned int sched_boost);
extern void schedutil_set_down_rate_limit(unsigned int limit_us);
extern int elevator_change_queue(struct request_queue *q, const char *name);

static void set_device_scheduler(int major, int minor)
{
	struct gendisk *disk;
	struct request_queue *q;

	disk = get_gendisk(MKDEV(major, minor), NULL);
	if (!disk) {
		pr_err("hammerhead: get_gendisk(%u,%u) failed\n", major, minor);
		return;
	}
	q = disk->queue;
	if (q && q->elevator) {
		pr_info("hammerhead: setting deadline on %d:%d\n", major, minor);
		elevator_change_queue(q, "deadline");
	} else {
		pr_err("hammerhead: no elevator for %d:%d\n", major, minor);
	}
	put_disk(disk);
}

static void reapply_optimizations_work(struct work_struct *work);
static DECLARE_DELAYED_WORK(hammerhead_opt, reapply_optimizations_work);

static void reapply_optimizations_work(struct work_struct *work)
{
	static int run_count = 0;
	run_count++;

	vm_swappiness = 20;

	/* Direct I/O scheduler change */
	set_device_scheduler(8, 0);   /* sda */
	set_device_scheduler(8, 16);  /* sdb */

	/* Direct CPU boost params */
	cpu_boost_set_params(NULL, 40, 1);

	/* Direct schedutil rate limit change */
	schedutil_set_down_rate_limit(5000);

	pr_info("hammerhead_opt: re-apply run %d/4\n", run_count);

	if (run_count < 4)
		schedule_delayed_work(&hammerhead_opt,
			msecs_to_jiffies(run_count == 1 ? 60000 :
					  run_count == 2 ? 120000 : 300000));
}

static int __init hammerhead_init(void)
{
	vm_swappiness = 20;

	pr_info("hammerhead_opt: init - restoring optimized settings after vendor init\n");

	schedule_delayed_work(&hammerhead_opt, msecs_to_jiffies(60000));

	return 0;
}
late_initcall(hammerhead_init);
